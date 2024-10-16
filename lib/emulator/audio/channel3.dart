class Channel3 {
  int nrx0 = 0; // Sound ON/OFF (NR30)
  int nrx1 = 0; // Sound Length (NR31)
  int nrx2 = 0; // Output Level (NR32)
  int nrx3 = 0; // Frequency low (NR33)
  int nrx4 = 0; // Frequency high + Control (NR34)

  int frequency = 0; // Current frequency
  int cycleLength = 0; // Frequency timer period
  int lengthCounter = 0; // Length counter
  bool enabled = false; // Whether the channel is currently enabled
  bool lengthEnabled = false; // Length counter enabled flag
  int volume = 0;
  int outputLevel = 0;
  int currentSampleIndex = 0;

  int volumeShift = 0; // Volume shift (determines the output level)
  int waveformPhase = 0; // Track the current phase in the waveform cycle
  int sampleIndex = 0; // Index for the current sample in the waveform
  int sampleBuffer = 0; // Holds the current waveform sample

  // 32 4-bit waveform samples
  List<int> waveformData = List<int>.filled(32, 0); // Initialize with 0s

  // NR30: Sound ON/OFF (NR30)
  int readNR30() => nrx0 | 0x7F;
  void writeNR30(int value) {
    nrx0 = value;

    // Enable or disable the channel
    enabled = (value & 0x80) != 0;

    if (!enabled) {
      reset(); // Reset the channel when disabled
    }
  }

  // NR31: Sound Length (NR31)
  int readNR31() => nrx1 | 0xFF;
  void writeNR31(int value) {
    nrx1 = value;

    // Set length counter (256 steps)
    lengthCounter = 256 - value;
  }

  // NR32: Output Level (NR32)
  int readNR32() => nrx2 | 0x9F;
  void writeNR32(int value) {
    nrx2 = value;

    // Output level (00 = mute, 01 = full volume, 10 = half, 11 = quarter)
    outputLevel = (value >> 5) & 0x03;
  }

  // NR33: Frequency Low (NR33)
  int readNR33() => nrx3 | 0xFF;
  void writeNR33(int value) {
    nrx3 = value;

    // Lower 8 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | value;
  }

  // NR34: Frequency High + Control (NR34)
  int readNR34() => nrx4 | 0xBF;
  void writeNR34(int value) {
    nrx4 = value;

    // Higher 3 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | nrx3;

    if ((value & 0x80) != 0) {
      // Trigger the channel
      waveformPhase = 0;
      enabled = true;
    }

    // Set length enabled
    lengthEnabled = (value & 0x40) != 0;
  }

  // Restart the waveform generation
  void restartWaveform() {
    waveformPhase = 0; // Reset phase
    sampleIndex = 0; // Start from the first sample
    sampleBuffer = waveformData[sampleIndex]; // Load the first sample
  }

  // Length counter logic
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Disable the channel when the length expires
      }
    }
  }

  // Waveform tick function
  void tick(int delta) {
    if (!enabled) return;

    waveformPhase += delta; // Advance the phase by the CPU cycles

    // Check if we've reached the end of the current sample cycle
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0; // Reset the phase
      sampleIndex = (sampleIndex + 1) % 32; // Move to the next sample
      sampleBuffer = waveformData[sampleIndex]; // Load the current sample
    }
  }

  // Get the output of Channel 3
  int getOutput() {
    if (!enabled || outputLevel == 0) return 0; // Return 0 if muted or disabled

    // Advance waveform phase based on the cycle length
    waveformPhase += 1;
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0;
      currentSampleIndex = (currentSampleIndex + 1) % 32;
      sampleBuffer = waveformData[currentSampleIndex];
    }

    // Scale output based on the output level from NR32
    int scaledOutput = (sampleBuffer >> (4 - outputLevel)) & 0xF;
    return (scaledOutput * 2) - 15; // Normalize to signed value (-15 to 15)
  }

  // Reset the state of Channel 3
  void reset() {
    nrx0 = 0;
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    frequency = 0;
    enabled = false;
    volumeShift = 0;
    lengthCounter = 0;
    waveformPhase = 0;
    sampleIndex = 0;
    sampleBuffer = 0;
    waveformData.fillRange(0, waveformData.length, 0); // Clear waveform data
  }

  // Handle waveform memory reads
  int readWaveform(int address) {
    return waveformData[address % 32];
  }

  // Handle waveform memory writes
  void writeWaveform(int address, int value) {
    waveformData[address % 32] = value & 0xFF; // 8-bit waveform sample
  }
}
