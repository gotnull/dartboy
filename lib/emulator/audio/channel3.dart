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
    bool newLengthEnable = (value & 0x40) != 0;
    bool triggering = (value & 0x80) != 0;
    nr34 = value;

    frequency = (nr34 & 0x07) << 8 | nr33;

    bool nextStepDoesntClockLength = (frameSequencer & 1) == 0;
    if (nextStepDoesntClockLength &&
        newLengthEnable &&
        !lengthEnabled &&
        lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0 && !triggering) {
        enabled = false;
      }
    }

    lengthEnabled = newLengthEnable;

    if (triggering) {
      trigger();
    }
  }

  // Trigger the channel. Reload of timers/length happens regardless of DAC;
  // only the channel-enabled flag depends on the DAC.
  void trigger() {
    // Channel 3 period = 2 * (2048 - frequency). Add 6 T-cycle delay on trigger.
    frequencyTimer = 2 * (2048 - frequency) + 6;

    // Pan Docs: position is reset to 0, but the sample buffer is NOT refilled.
    // Whatever was last latched into currentSample stays until the channel
    // reads its next sample.
    sampleIndex = 0;

    if (lengthCounter == 0) {
      lengthCounter = 256;
      bool nextStepDoesntClockLength = (frameSequencer & 1) == 0;
      if (lengthEnabled && nextStepDoesntClockLength) {
        lengthCounter = 255;
      }
    }

    enabled = dacEnabled;
  }

  // Update frequency timer - Channel 3 period formula
  void updateFrequencyTimer() {
    frequencyTimer = 2 * (2048 - frequency);
    if (frequencyTimer <= 0) frequencyTimer = 2;
  }

  /// Time-weighted-output accumulator (see Channel1 for the why).
  double _outAcc = 0.0;
  int _cycAcc = 0;

  // Frequency timer; splits each tick into segments at every wave-position
  // change so we can average the output over the audio sample period.
  void tick(int cycles) {
    if (!enabled) {
      _cycAcc += cycles;
      return;
    }

    while (cycles > 0) {
      final int instOut = _instantaneousOutput();

      int segment = frequencyTimer;
      if (segment <= 0) segment = 1;
      if (segment > cycles) segment = cycles;

      _outAcc += instOut * segment;
      _cycAcc += segment;

      cycles -= segment;
      frequencyTimer -= segment;

      if (frequencyTimer <= 0) {
        int period = 2 * (2048 - frequency);
        if (period <= 0) period = 2;
        frequencyTimer += period;
        advanceSampleIndex();
      }
    }
  }

  int _instantaneousOutput() {
    switch (volumeShift) {
      case 0:
        return 0;
      case 1:
        return currentSample;
      case 2:
        return currentSample >> 1;
      case 3:
        return currentSample >> 2;
      default:
        return 0;
    }
  }

  double getAveragedOutput() {
    if (!enabled || !dacEnabled || _cycAcc <= 0) {
      _outAcc = 0;
      _cycAcc = 0;
      return 0.0;
    }
    final double avg = _outAcc / _cycAcc;
    _outAcc = 0;
    _cycAcc = 0;
    return avg;
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

  // Write to Waveform RAM (0xFF30 - 0xFF3F).
  // CGB behavior: writes while the channel is playing redirect to the byte
  // currently being read by the wave-position counter.
  void writeWaveformRAM(int address, int value) {
    int index = address - 0x30;
    if (enabled && dacEnabled) {
      index = (sampleIndex >> 1) & 0x0F;
    }
    waveformRAM[index] = value & 0xFF;
  }

  // Reset the channel state. Wave RAM is preserved by default since it survives
  // APU power-off; only a hard reset (emulator boot) clears it.
  void reset({bool clearWaveRam = false}) {
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
    if (clearWaveRam) {
      waveformRAM.fillRange(0, waveformRAM.length, 0);
    }
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
