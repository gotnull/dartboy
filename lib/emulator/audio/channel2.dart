class Channel2 {
  // Registers
  int nr21 = 0; // Sound Length/Wave Duty (NR21)
  int nr22 = 0; // Volume Envelope (NR22)
  int nr23 = 0; // Frequency low (NR23)
  int nr24 = 0; // Frequency high + Control (NR24)

  // Internal state
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer (counts down in CPU cycles)
  int dutyStep = 0; // Current duty step position (0-7)
  int volume = 0; // Current volume (0-15)
  int lengthCounter = 0; // Length counter (0-64)

  // Envelope state
  int envelopeTimer = 0; // Envelope timer
  int envelopePeriod = 0; // Envelope period (0-7)
  bool envelopeIncrease = false; // Envelope direction

  // Control flags
  bool enabled = false; // Channel enabled flag
  bool dacEnabled = false; // DAC enabled (NR22 bits 3-7 not all zero)
  bool lengthEnabled = false; // Length counter enabled

  // Duty cycle patterns (Pan Docs specification)
  static const List<List<int>> dutyPatterns = [
    [0, 0, 0, 0, 0, 0, 0, 1], // 12.5%
    [0, 0, 0, 0, 0, 0, 1, 1], // 25%
    [0, 0, 0, 0, 1, 1, 1, 1], // 50%
    [1, 1, 1, 1, 1, 1, 0, 0], // 75%
  ];

  // Duty cycle index (0-3)
  int dutyCycle = 0;

  // Constructor
  Channel2();

  // NR21: Sound Length / Waveform Duty
  int readNR21() =>
      (nr21 & 0xC0) | 0x3F; // Only bits 6-7 readable, bits 0-5 always 1
  void writeNR21(int value) {
    nr21 = value;
    dutyCycle = (nr21 >> 6) & 0x03;
    int lengthData = nr21 & 0x3F;
    lengthCounter = 64 - lengthData;
  }

  // NR22: Volume Envelope
  int readNR22() => nr22; // Returns stored value per KameBoyColor
  void writeNR22(int value) {
    nr22 = value;
    // Volume is NOT set here - only loaded from NR22 on trigger
    envelopeIncrease = (nr22 & 0x08) != 0;
    envelopePeriod = nr22 & 0x07;
    dacEnabled = (nr22 & 0xF8) != 0;
    if (!dacEnabled) {
      enabled = false;
    }
  }

  // NR23: Frequency Low
  int readNR23() => 0xFF; // Write-only register
  void writeNR23(int value) {
    nr23 = value;
    // Only the period changes; the running countdown keeps draining and
    // reloads with the new period when it next expires. Resetting the
    // countdown on every register write makes pitch slides choppy.
    frequency = (nr24 & 0x07) << 8 | nr23;
  }

  // NR24: Frequency High and Control
  int readNR24() =>
      (nr24 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR24(int value) {
    bool newLengthEnable = (value & 0x40) != 0;
    bool triggering = (value & 0x80) != 0;
    nr24 = value;

    // Period only — see writeNR23.
    frequency = (nr24 & 0x07) << 8 | nr23;

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
    frequencyTimer = 4 * (2048 - frequency);
    dutyStep = 0;

    envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
    volume = (nr22 >> 4) & 0x0F;

    if (lengthCounter == 0) {
      lengthCounter = 64;
      bool nextStepDoesntClockLength = (frameSequencer & 1) == 0;
      if (lengthEnabled && nextStepDoesntClockLength) {
        lengthCounter = 63;
      }
    }

    enabled = dacEnabled;
  }

  // Update frequency timer - back to working formula
  void updateFrequencyTimer() {
    frequencyTimer = 4 * (2048 - frequency);
    if (frequencyTimer <= 0) frequencyTimer = 4;
  }

  /// See Channel1 for the rationale — this is the time-weighted output
  /// accumulator that lets us emit a band-limited average per audio sample
  /// instead of a single instantaneous snapshot.
  double _outAcc = 0.0;
  int _cycAcc = 0;

  void tick(int cycles) {
    if (!enabled) {
      _cycAcc += cycles;
      return;
    }

    while (cycles > 0) {
      final int dutyBit = dutyPatterns[dutyCycle][dutyStep];
      final int instOut = dutyBit == 1 ? volume : 0;

      int segment = frequencyTimer;
      if (segment <= 0) segment = 1;
      if (segment > cycles) segment = cycles;

      _outAcc += instOut * segment;
      _cycAcc += segment;

      cycles -= segment;
      frequencyTimer -= segment;

      if (frequencyTimer <= 0) {
        dutyStep = (dutyStep + 1) & 7;
        int period = 4 * (2048 - frequency);
        if (period <= 0) period = 4;
        frequencyTimer += period;
      }
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

  // Update length counter (called by frame sequencer)
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }

  // Update envelope - Pan Docs accurate
  void updateEnvelope() {
    if (envelopePeriod != 0 && enabled) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopePeriod;
        if (envelopeIncrease) {
          if (volume < 15) volume++;
        } else {
          if (volume > 0) volume--;
        }
      }
    }
  }

  // Get the output sample for the current state
  // Returns digital value (0-15) that will be converted by DAC
  int getOutput() {
    // If channel or DAC is disabled, output 0
    if (!enabled || !dacEnabled) return 0;

    // 0-based duty step index (0-7)
    int dutyBit = dutyPatterns[dutyCycle][dutyStep];

    // Output volume when duty is high, 0 when low
    return dutyBit == 1 ? volume : 0;
  }

  // Reset the channel
  void reset() {
    nr21 = 0;
    nr22 = 0;
    nr23 = 0;
    nr24 = 0;
    frequency = 0;
    frequencyTimer = 0;
    dutyStep = 0;
    envelopeTimer = 0;
    lengthCounter = 0;
    volume = 0;
    enabled = false;
    dacEnabled = false;
    lengthEnabled = false;
    envelopeIncrease = false;
    envelopePeriod = 0;
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
