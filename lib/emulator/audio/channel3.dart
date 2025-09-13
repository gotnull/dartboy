class Channel3 {
  // Registers
  int nr30 = 0; // Sound ON/OFF (NR30)
  int nr31 = 0; // Sound Length (NR31)
  int nr32 = 0; // Output Level (NR32)
  int nr33 = 0; // Frequency low (NR33)
  int nr34 = 0; // Frequency high + Control (NR34)

  // Internal state
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer (counts down in CPU cycles)
  int sampleIndex = 0; // Current sample index (0-31)
  int currentSample = 0; // Current 4-bit sample value
  int lengthCounter = 0; // Length counter (0-256)

  // Volume control
  int volumeShift = 0; // Volume shift (0: Mute, 1: 100%, 2: 50%, 3: 25%)

  // Control flags
  bool enabled = false; // Channel enabled flag
  bool dacEnabled = false; // DAC enabled (NR30 bit 7)
  bool lengthEnabled = false; // Length counter enabled

  // Waveform RAM (16 bytes storing 32 4-bit samples)
  // Pan Docs: "32 4-bit samples played in sequence"
  List<int> waveformRAM = List<int>.filled(16, 0);

  // Constructor
  Channel3();

  // NR30: Sound ON/OFF
  int readNR30() => (nr30 & 0x80) | 0x7F; // Only bit 7 readable, others read as 1
  void writeNR30(int value) {
    nr30 = value;
    dacEnabled = (nr30 & 0x80) != 0; // Bit 7 controls DAC
    if (!dacEnabled) {
      enabled = false; // Disable channel if DAC is off
    }
  }

  // NR31: Sound Length
  int readNR31() => 0xFF; // Write-only register
  void writeNR31(int value) {
    nr31 = value;
    lengthCounter = 256 - nr31; // Length counter range: 0-255
  }

  // NR32: Output Level
  int readNR32() => (nr32 & 0x60) | 0x9F; // Only bits 5-6 readable, others read as 1
  void writeNR32(int value) {
    nr32 = value;
    volumeShift = (nr32 >> 5) & 0x03;
  }

  // NR33: Frequency Low
  int readNR33() => 0xFF; // Write-only register
  void writeNR33(int value) {
    nr33 = value;
    frequency = (nr34 & 0x07) << 8 | nr33;
  }

  // NR34: Frequency High and Control
  int readNR34() => (nr34 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR34(int value) {
    bool wasLengthEnabled = lengthEnabled;
    nr34 = value;
    lengthEnabled = (nr34 & 0x40) != 0;
    frequency = (nr34 & 0x07) << 8 | nr33;
    
    // Length counter extra clocking when enabling length
    if (!wasLengthEnabled &&
        lengthEnabled &&
        lengthCounter > 0 &&
        (frameSequencer & 1) == 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
    
    if ((nr34 & 0x80) != 0) {
      trigger();
    }
  }


  // Trigger the channel (on write to NR34 with bit 7 set)
  // Pan Docs: "Triggering a sound restarts it from the beginning"
  void trigger() {
    // Channel is enabled only if DAC is enabled
    enabled = dacEnabled;

    if (enabled) {
      // Reset frequency timer with initial period
      frequencyTimer = 2 * (2048 - frequency);

      // Reset sample index to start of wave RAM
      sampleIndex = 0;

      // Read first sample from wave RAM
      int firstByte = waveformRAM[0];
      currentSample = (firstByte >> 4) & 0x0F; // High nibble of first byte

      // Length counter handling
      if (lengthCounter == 0) {
        lengthCounter = 256; // Wave channel has 256-step length counter
        // Extra clocking if frame sequencer is about to clock length
        if (lengthEnabled && (frameSequencer & 1) == 0) {
          lengthCounter--;
          if (lengthCounter == 0) enabled = false;
        }
      }
    }
  }

  // Update the frequency timer based on the current frequency
  void updateFrequencyTimer() {
    frequencyTimer = (2048 - frequency) * 2;
    if (frequencyTimer <= 0) frequencyTimer = 2; // Ensure minimum period
  }

  // Update method called every CPU cycle - optimized for performance
  // Update method called every CPU cycle - cycle accurate per Pan Docs
  void tick(int cycles) {
    if (!enabled) return;

    // Frequency timer decrements every CPU cycle
    // Pan Docs: "sample index advances at 32x channel frequency"
    // Period = 2 * (2048 - frequency) CPU cycles (different from pulse channels)
    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      // Calculate the reload period
      int period = 2 * (2048 - frequency);
      if (period <= 0) period = 2; // Minimum period to prevent locks

      // Reload timer
      frequencyTimer += period;

      // Advance sample index and read new sample
      advanceSampleIndex();
    }
  }

  // Advance sample index and read new 4-bit sample from wave RAM
  // Pan Docs: "sample index counter advances at 32x channel frequency"
  void advanceSampleIndex() {
    // Advance sample index (0-31, wrapping)
    sampleIndex = (sampleIndex + 1) % 32;

    // Read new 4-bit sample from wave RAM
    // Wave RAM stores 32 4-bit samples in 16 bytes
    int byteIndex = sampleIndex ~/ 2;
    int sampleData = waveformRAM[byteIndex];

    // Extract 4-bit sample (high nibble for even indices, low for odd)
    if (sampleIndex % 2 == 0) {
      currentSample = (sampleData >> 4) & 0x0F; // High nibble
    } else {
      currentSample = sampleData & 0x0F; // Low nibble
    }
  }

  // Update length counter (called by frame sequencer)
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }

  // Get the output sample for the current state
  // Returns digital value (0-15) that will be converted by DAC
  int getOutput() {
    // If channel or DAC is disabled, output 0
    if (!enabled || !dacEnabled) return 0;

    // Apply volume control via right shift
    int outputLevel;
    switch (volumeShift) {
      case 0:
        outputLevel = 0; // Mute (0%)
        break;
      case 1:
        outputLevel = currentSample; // 100%
        break;
      case 2:
        outputLevel = currentSample >> 1; // 50%
        break;
      case 3:
        outputLevel = currentSample >> 2; // 25%
        break;
      default:
        outputLevel = 0;
        break;
    }

    // Return digital value (0-15) for DAC conversion
    return outputLevel & 0x0F;
  }

  // Read from Waveform RAM (0xFF30 - 0xFF3F)
  int readWaveformRAM(int address) {
    int index = address - 0xFF30;
    return waveformRAM[index];
  }

  // Write to Waveform RAM (0xFF30 - 0xFF3F)
  void writeWaveformRAM(int address, int value) {
    int index = address - 0xFF30;
    waveformRAM[index] = value & 0xFF;
  }

  // Reset the channel
  void reset() {
    nr30 = 0;
    nr31 = 0;
    nr32 = 0;
    nr33 = 0;
    nr34 = 0;
    frequency = 0;
    frequencyTimer = 0;
    sampleIndex = 0;
    currentSample = 0;
    lengthCounter = 0;
    volumeShift = 0;
    enabled = false;
    dacEnabled = false;
    lengthEnabled = false;
    waveformRAM.fillRange(0, waveformRAM.length, 0);
  }

  // Frame sequencer reference (needs to be set from Audio class)
  int frameSequencer = 0;

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }
}
