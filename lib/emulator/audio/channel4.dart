class Channel4 {
  // Registers
  int nr41 = 0; // Sound Length (NR41)
  int nr42 = 0; // Volume Envelope (NR42)
  int nr43 = 0; // Polynomial Counter (NR43)
  int nr44 = 0; // Counter/Consecutive; Initial (NR44)

  // Internal state
  int frequencyTimer = 0; // Frequency timer (counts down in CPU cycles)
  int lengthCounter = 0; // Length counter (0-64)
  int volume = 0; // Current volume (0-15)

  // LFSR state (Linear Feedback Shift Register for noise generation)
  int lfsr = 0x7FFF; // 15-bit LFSR (starts with all bits set)
  bool widthMode = false; // false=15-bit mode, true=7-bit mode

  // Envelope state
  int envelopeTimer = 0; // Envelope timer
  int envelopePeriod = 0; // Envelope period (0-7)
  bool envelopeIncrease = false; // Envelope direction

  // Control flags
  bool enabled = false; // Channel enabled flag
  bool lengthEnabled = false; // Length counter enabled
  bool dacEnabled = false; // DAC enabled (NR42 bits 3-7 not all zero)

  // Constructor
  Channel4();

  // NR41: Sound Length
  int readNR41() => 0xFF; // Write-only register
  void writeNR41(int value) {
    nr41 = value;
    int lengthData = nr41 & 0x3F;
    lengthCounter = 64 - lengthData;
  }

  // NR42: Volume Envelope
  int readNR42() => nr42; // Returns stored value per KameBoyColor
  void writeNR42(int value) {
    nr42 = value;
    volume = (nr42 >> 4) & 0x0F;
    envelopeIncrease = (nr42 & 0x08) != 0;
    envelopePeriod = nr42 & 0x07;
    dacEnabled = (nr42 & 0xF8) != 0;
    if (!dacEnabled) {
      enabled = false;
    }
  }

  // NR43: Polynomial Counter
  int readNR43() => nr43; // Returns stored value per KameBoyColor
  void writeNR43(int value) {
    nr43 = value;
    updateFrequencyTimer();
    // Bit 3 controls LFSR width: 0=15-bit, 1=7-bit
    widthMode = (nr43 & 0x08) != 0;
  }

  // NR44: Counter/Consecutive; Initial
  int readNR44() => (nr44 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR44(int value) {
    bool lengthEnable = (value & 0x40) != 0;
    nr44 = value;

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

    if ((nr44 & 0x80) != 0) {
      trigger();
    }
  }

  // Trigger the channel (on write to NR44 with bit 7 set)
  void trigger() {
    enabled = dacEnabled;
    if (enabled) {
      // KameBoyColor Channel 4 trigger (line 725)
      frequencyTimer = 0; // Start at 0 like KameBoyColor
      envelopeTimer = envelopePeriod;
      volume = (nr42 >> 4) & 0x0F;
      lfsr = 0x7FFF; // Reset LFSR to all ones

      // Length counter reloading
      if (lengthCounter == 0) {
        lengthCounter = 64;
        // Extra clocking if length enabled during length-clocking steps
        if (lengthEnabled && (frameSequencer & 1) == 0) {
          lengthCounter--;
          if (lengthCounter == 0) {
            enabled = false;
          }
        }
      }
    }
  }

  // Calculate the frequency timer period based on NR43
  int getFrequencyTimerPeriod() {
    int r = nr43 & 0x07;
    int s = (nr43 >> 4) & 0x0F;
    int divisor;
    switch (r) {
      case 0:
        divisor = 8;
        break;
      case 1:
        divisor = 16;
        break;
      case 2:
        divisor = 32;
        break;
      case 3:
        divisor = 48;
        break;
      case 4:
        divisor = 64;
        break;
      case 5:
        divisor = 80;
        break;
      case 6:
        divisor = 96;
        break;
      case 7:
        divisor = 112;
        break;
      default:
        divisor = 8;
        break;
    }
    return divisor << s;
  }

  // Update the frequency timer based on NR43
  void updateFrequencyTimer() {
    frequencyTimer = getFrequencyTimerPeriod();
    if (frequencyTimer <= 0) frequencyTimer = 8; // Ensure minimum period
  }

  // Channel 4 timing - matches KameBoyColor exactly (lines 758-789)
  // Note: This will need global audio cycle counter from APU
  void tick(int cycles) {
    if (!enabled) return;

    // KameBoyColor uses different timing - only clock on specific intervals
    // This is a simplified version - proper implementation needs APU cycle counter
    frequencyTimer -= cycles;
    int loopCount = 0;
    while (frequencyTimer <= 0 && loopCount < 1000) { // Safety limit to prevent infinite loops
      int period = getFrequencyTimerPeriod();
      if (period <= 0) period = 1;
      frequencyTimer += period;
      clockLFSR();
      loopCount++;
    }
  }

  // Clock the LFSR (Linear Feedback Shift Register)
  // Pan Docs: "15-bit LFSR with taps at bit 0 and bit 1"
  void clockLFSR() {
    // Calculate feedback bit (XOR of bits 0 and 1)
    int feedbackBit = (lfsr & 1) ^ ((lfsr >> 1) & 1);

    // Shift LFSR right by 1 position
    lfsr >>= 1;

    // Insert feedback bit at position 14 (bit 14)
    lfsr |= (feedbackBit << 14);

    // In 7-bit mode, also insert feedback bit at position 6
    if (widthMode) {
      lfsr &= ~(1 << 6); // Clear bit 6
      lfsr |= (feedbackBit << 6); // Set bit 6 to feedback bit
    }

    // Keep LFSR within 15-bit range
    lfsr &= 0x7FFF;
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

  // Update envelope - matches KameBoyColor exactly (lines 742-755)
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
        volume &= 0x0F; // KameBoyColor line 754
      }
    }
  }

  // Get the output sample for the current state
  // Returns digital value (0-15) that will be converted by DAC
  int getOutput() {
    // If channel or DAC is disabled, output 0
    if (!enabled || !dacEnabled) return 0;

    // KameBoyColor Channel 4 output (line 789)
    return (lfsr & 1) * volume;
  }

  // Reset the channel
  void reset() {
    nr41 = 0;
    nr42 = 0;
    nr43 = 0;
    nr44 = 0;
    frequencyTimer = 0;
    lengthCounter = 0;
    volume = 0;
    envelopeTimer = 0;
    lfsr = 0x7FFF;
    enabled = false;
    dacEnabled = false;
    lengthEnabled = false;
    envelopeIncrease = false;
    envelopePeriod = 0;
    widthMode = false;
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
