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
    [0, 0, 0, 0, 0, 0, 0, 1], // 12.5% (one high bit)
    [1, 0, 0, 0, 0, 0, 0, 1], // 25% (two high bits)
    [1, 0, 0, 0, 0, 1, 1, 1], // 50% (four high bits)
    [0, 1, 1, 1, 1, 1, 1, 0], // 75% (six high bits - inverted 25%)
  ];

  // Duty cycle index (0-3)
  int dutyCycle = 0;

  // Constructor
  Channel2();

  // NR21: Sound Length / Waveform Duty
  int readNR21() => (nr21 & 0xC0) | 0x3F; // Only bits 6-7 readable, bits 0-5 always 1
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
    volume = (nr22 >> 4) & 0x0F;
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
    frequency = (nr24 & 0x07) << 8 | nr23;
    updateFrequencyTimer();
  }

  // NR24: Frequency High and Control
  int readNR24() => (nr24 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR24(int value) {
    bool lengthEnable = (value & 0x40) != 0;
    nr24 = value;

    frequency = (nr24 & 0x07) << 8 | nr23;
    updateFrequencyTimer();

    // KameBoyColor obscure behavior: Length counter extra clocking
    bool nextStepDoesntUpdate = (frameSequencer & 1) == 0;
    if (nextStepDoesntUpdate) {
      if (lengthEnable && !lengthEnabled && lengthCounter > 0) {
        lengthCounter--;
        if (lengthCounter == 0) {
          enabled = false;
        }
      }
    }

    // More obscure behavior from KameBoyColor
    if ((value & 0x80) != 0 && lengthEnabled && lengthCounter == 64) {
      lengthCounter--;
    }

    // Blargg test 2 behavior
    if ((value & 0x80) != 0 && lengthCounter == 0) {
      lengthCounter = 64;
    }

    lengthEnabled = lengthEnable;

    if ((nr24 & 0x80) != 0) {
      trigger();
    }
  }

  // Trigger the channel (on write to NR24 with bit 7 set)
  // Trigger the channel (on write to NR24 with bit 7 set)
  // Pan Docs: "Triggering a sound restarts it from the beginning"
  void trigger() {
    // Channel is enabled only if DAC is enabled
    enabled = dacEnabled;


    if (enabled) {
      // Reset frequency timer - back to working formula
      frequencyTimer = 4 * (2048 - frequency);

      // KameBoyColor: waveform_idx starts at 0
      dutyStep = 0;

      // Reset envelope - KameBoyColor behavior
      envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
      volume = (nr22 >> 4) & 0x0F; // Initial volume from NR22 bits 4-7

      // Length counter handling
      if (lengthCounter == 0) {
        lengthCounter = 64; // Full length
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

  // Update frequency timer - back to working formula
  void updateFrequencyTimer() {
    frequencyTimer = 4 * (2048 - frequency);
    if (frequencyTimer <= 0) frequencyTimer = 4;
  }

  // Frequency timer - back to DOWN counting to avoid lockups
  void tick(int cycles) {
    if (!enabled) return;

    // Back to DOWN counting but with correct period calculation
    frequencyTimer -= cycles;
    int loopCount = 0;
    while (frequencyTimer <= 0 && loopCount < 1000) { // Safety limit to prevent infinite loops
      // KameBoyColor waveform advance logic
      if (dutyStep == 8) {
        dutyStep = 1;
      } else {
        dutyStep++;
      }

      // Use proper Game Boy frequency formula
      int period = 4 * (2048 - frequency);
      if (period <= 0) period = 4;
      frequencyTimer += period;
      loopCount++;
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

  // Update envelope - matches KameBoyColor exactly (lines 598-611)
  void updateEnvelope() {
    // KameBoyColor checks volume_pace != 0
    if (envelopePeriod != 0 && enabled) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopePeriod;
        if (envelopeIncrease) {
          volume++;
        } else {
          if (volume != 0) {
            volume--;
          }
        }
        volume &= 0x0F; // KameBoyColor line 610
      }
    }
  }

  // Get the output sample for the current state
  // Returns digital value (0-15) that will be converted by DAC
  int getOutput() {
    // If channel or DAC is disabled, output 0
    if (!enabled || !dacEnabled) return 0;

    // Safe duty pattern indexing - ensure index is always 0-7
    int index = (dutyStep - 1) % 8;
    if (index < 0) index = 7; // Handle dutyStep = 0 case
    int dutyBit = dutyPatterns[dutyCycle][index];

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
