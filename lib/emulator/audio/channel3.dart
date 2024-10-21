class Channel3 {
  // Registers
  int nr30 = 0; // Sound ON/OFF (NR30)
  int nr31 = 0; // Sound Length (NR31)
  int nr32 = 0; // Output Level (NR32)
  int nr33 = 0; // Frequency low (NR33)
  int nr34 = 0; // Frequency high + Control (NR34)

  // Internal variables
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer
  int lengthCounter = 0; // Length counter
  int volumeShift = 0; // Volume shift (0: Mute, 1: 100%, 2: 50%, 3: 25%)
  int waveformIndex = 0; // Index in the waveform RAM (0-31)
  int sampleBuffer = 0; // Current sample (4 bits)
  bool enabled = false; // Channel enabled flag
  bool dacEnabled = false; // DAC enabled flag

  // Waveform RAM (32 bytes, 64 nibbles)
  List<int> waveformRAM = List<int>.filled(16, 0); // 16 bytes (32 samples)

  // Constructor
  Channel3();

  // NR30: Sound ON/OFF
  int readNR30() => nr30 | 0x7F; // Bit 7 is read-only
  void writeNR30(int value) {
    nr30 = value;
    dacEnabled = (nr30 & 0x80) != 0;
    if (!dacEnabled) {
      enabled = false;
    }
  }

  // NR31: Sound Length
  int readNR31() => 0xFF; // Write-only register
  void writeNR31(int value) {
    nr31 = value;
    lengthCounter = 256 - nr31; // Length counter range: 0-255
  }

  // NR32: Output Level
  int readNR32() => nr32 | 0x9F; // Bits 0-4 are unused/read-only
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
  int readNR34() => nr34 | 0xBF; // Bits 6-7 are unused/read-only
  void writeNR34(int value) {
    bool wasLengthEnabled = lengthEnabled;
    nr34 = value;
    lengthEnabled = (nr34 & 0x40) != 0;
    frequency = (nr34 & 0x07) << 8 | nr33;
    if ((nr34 & 0x80) != 0) {
      trigger();
    }
    if (!wasLengthEnabled &&
        lengthEnabled &&
        lengthCounter == 0 &&
        frameSequencer == 0) {
      lengthCounter = 255;
    }
  }

  // Length counter enabled flag
  bool lengthEnabled = false;

  // Trigger the channel (on write to NR34 with bit 7 set)
  void trigger() {
    enabled = dacEnabled;
    frequencyTimer = (2048 - frequency) * 2;
    waveformIndex = 0;
    lengthCounter = lengthCounter == 0 ? 256 : lengthCounter;
    sampleBuffer = 0;
  }

  // Update the frequency timer based on the current frequency
  void updateFrequencyTimer() {
    frequencyTimer = (2048 - frequency) * 2;
  }

  // Update method called every CPU cycle
  void tick(int cycles) {
    if (!enabled) return;

    // Frequency timer
    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      frequencyTimer += (2048 - frequency) * 2;
      advanceWaveform();
    }
  }

  // Advance the waveform index and update the sample buffer
  void advanceWaveform() {
    waveformIndex = (waveformIndex + 1) % 32; // 32 samples
    int byteIndex = waveformIndex ~/ 2;
    int sampleData = waveformRAM[byteIndex];

    if (waveformIndex % 2 == 0) {
      // High nibble
      sampleBuffer = (sampleData >> 4) & 0x0F;
    } else {
      // Low nibble
      sampleBuffer = sampleData & 0x0F;
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
  int getOutput() {
    if (!enabled || !dacEnabled) return 0;

    int outputLevel;
    switch (volumeShift) {
      case 0:
        outputLevel = 0; // Mute
        break;
      case 1:
        outputLevel = sampleBuffer; // 100%
        break;
      case 2:
        outputLevel = sampleBuffer >> 1; // 50%
        break;
      case 3:
        outputLevel = sampleBuffer >> 2; // 25%
        break;
      default:
        outputLevel = 0;
        break;
    }

    // Convert to signed value (-8 to +7)
    outputLevel -= 8;
    return outputLevel;
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
    waveformIndex = 0;
    sampleBuffer = 0;
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
