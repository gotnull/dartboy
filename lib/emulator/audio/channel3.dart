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
  int readNR30() =>
      (nr30 & 0x80) | 0x7F; // Only bit 7 readable, others read as 1
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
  int readNR32() =>
      (nr32 & 0x60) | 0x9F; // Only bits 5-6 readable, others read as 1
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
  int readNR34() =>
      (nr34 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR34(int value) {
    bool lengthEnable = (value & 0x40) != 0;
    nr34 = value;

    frequency = (nr34 & 0x07) << 8 | nr33;

    // KameBoyColor obscure behavior: Length counter extra clocking
    // next_step_doesnt_update = (frame_sequencer & 1) == 0
    // This means even steps (0,2,4,6) are the ones that DON'T update yet
    bool nextStepDoesntUpdate = (frameSequencer & 1) == 0;
    if (nextStepDoesntUpdate) {
      if (lengthEnable && !lengthEnabled && lengthCounter > 0) {
        lengthCounter--;
        if (lengthCounter == 0) {
          enabled = false;
        }
      }
    }

    // More obscure behavior from KameBoyColor - Channel 3 has 256 length
    if ((value & 0x80) != 0 && lengthEnabled && lengthCounter == 256) {
      lengthCounter--;
    }

    // Blargg test 2 behavior
    if ((value & 0x80) != 0 && lengthCounter == 0) {
      lengthCounter = 256;
    }

    lengthEnabled = lengthEnable;

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
      // Channel 3 period = 2 * (2048 - frequency). Add 6 T-cycle delay on trigger.
      frequencyTimer = 2 * (2048 - frequency) + 6;

      // Reset sample index to 0 and read initial sample
      sampleIndex = 0;
      currentSample = (waveformRAM[0] >> 4) & 0x0F; // High nibble of byte 0

      // Length counter handling
      if (lengthCounter == 0) {
        lengthCounter = 256; // Wave channel has 256-step length counter
        // Extra clocking if length enabled during even steps (next step doesn't update)
        bool nextStepDoesntUpdate = (frameSequencer & 1) == 0;
        if (lengthEnabled && nextStepDoesntUpdate) {
          lengthCounter--;
          if (lengthCounter == 0) {
            enabled = false;
          }
        }
      }
    }
  }

  // Update frequency timer - Channel 3 period formula
  void updateFrequencyTimer() {
    frequencyTimer = 2 * (2048 - frequency);
    if (frequencyTimer <= 0) frequencyTimer = 2;
  }

  // Update method called every CPU cycle - optimized for performance
  // Update method - Channel 3 frequency timer
  void tick(int cycles) {
    if (!enabled) return;

    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      // Reload with correct Channel 3 period: 2 * (2048 - frequency)
      int period = 2 * (2048 - frequency);
      if (period <= 0) period = 2;
      frequencyTimer += period;

      // Advance sample index and read new sample
      advanceSampleIndex();
    }
  }

  // Advance sample index - 0-based (0-31)
  void advanceSampleIndex() {
    // Advance to next sample position (0-31, wrapping)
    sampleIndex = (sampleIndex + 1) & 31;

    // Read sample from wave RAM
    // Even positions = high nibble, odd positions = low nibble
    int sampleOffset = sampleIndex >> 1;
    int waveForm = waveformRAM[sampleOffset];

    if ((sampleIndex & 1) == 0) {
      currentSample = (waveForm >> 4) & 0x0F; // High nibble
    } else {
      currentSample = waveForm & 0x0F; // Low nibble
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

    // KameBoyColor Channel 3 output formula (line 697)
    return outputLevel;
  }

  // Read from Waveform RAM (0xFF30 - 0xFF3F)
  int readWaveformRAM(int address) {
    int index = address - 0x30;

    // Wave RAM corruption: if channel is playing, return the currently playing sample
    if (enabled && dacEnabled) {
      int currentByteIndex = (sampleIndex >> 1) & 0x0F;
      return waveformRAM[currentByteIndex];
    }

    return waveformRAM[index];
  }

  // Write to Waveform RAM (0xFF30 - 0xFF3F)
  void writeWaveformRAM(int address, int value) {
    int index = address - 0x30;
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
  int frameSequencerCycles = 0;

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }

  // Set frame sequencer cycles (called from Audio class)
  void setFrameSequencerCycles(int value) {
    frameSequencerCycles = value;
  }
}
