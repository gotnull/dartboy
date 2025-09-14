class Channel1 {
  // Registers
  int nr10 = 0; // Sweep (NR10)
  int nr11 = 0; // Sound Length/Wave Duty (NR11)
  int nr12 = 0; // Volume Envelope (NR12)
  int nr13 = 0; // Frequency low (NR13)
  int nr14 = 0; // Frequency high + Control (NR14)

  // Internal state
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer (counts down in CPU cycles)
  int dutyStep = 0; // Current duty step position (0-7)
  int volume = 0; // Current volume (0-15)
  int lengthCounter = 0; // Length counter (0-64)

  // Sweep state
  int sweepTimer = 0; // Sweep timer
  int sweepPeriod = 0; // Sweep period (0-7)
  int sweepShift = 0; // Sweep shift amount (0-7)
  bool sweepNegate = false; // Sweep direction (false=increase, true=decrease)
  bool sweepEnabled = false; // Internal sweep enable flag
  int shadowFrequency = 0; // Shadow frequency for sweep calculations
  bool sweepNegateModeUsed = false; // Tracks if negate mode has been used (obscure behavior)

  // Envelope state
  int envelopeTimer = 0; // Envelope timer
  int envelopePeriod = 0; // Envelope period (0-7)
  bool envelopeIncrease = false; // Envelope direction

  // Control flags
  bool enabled = false; // Channel enabled flag
  bool dacEnabled = false; // DAC enabled (NR12 bits 3-7 not all zero)
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
  Channel1();

  // NR10: Sweep Register
  int readNR10() => (nr10 & 0x7F) | 0x80; // Only bits 0-6 writable, bit 7 always 1
  void writeNR10(int value) {
    bool oldSweepNegate = sweepNegate;
    nr10 = value;
    sweepPeriod = (nr10 >> 4) & 0x07;
    sweepNegate = (nr10 & 0x08) != 0;
    sweepShift = nr10 & 0x07;

    // Obscure behavior: Clearing negate mode after it was used disables channel
    if (sweepNegateModeUsed && oldSweepNegate && !sweepNegate) {
      enabled = false;
    }

    // Update sweep enable based on Pan Docs: enabled if period OR shift non-zero
    // But also consider current sweep state for runtime changes
    if (sweepPeriod == 0 && sweepShift == 0) {
      sweepEnabled = false;
    } else {
      // Re-enable sweep if either period or shift becomes non-zero
      sweepEnabled = true;
      // If we just enabled a non-zero period, restart the sweep timer
      if (sweepPeriod > 0) {
        sweepTimer = sweepPeriod;
      }
    }
  }

  // NR11: Sound Length / Waveform Duty
  int readNR11() => (nr11 & 0xC0) | 0x3F; // Only bits 6-7 readable, bits 0-5 always 1
  void writeNR11(int value) {
    nr11 = value;
    dutyCycle = (nr11 >> 6) & 0x03;
    int lengthData = nr11 & 0x3F;
    lengthCounter = 64 - lengthData;
  }

  // NR12: Volume Envelope
  int readNR12() => nr12; // Returns stored value per KameBoyColor
  void writeNR12(int value) {
    nr12 = value;
    volume = (nr12 >> 4) & 0x0F;
    envelopeIncrease = (nr12 & 0x08) != 0;
    envelopePeriod = nr12 & 0x07;
    dacEnabled = (nr12 & 0xF8) != 0; // DAC enabled if bits 3-7 are not all zero
    if (!dacEnabled) {
      enabled = false; // Disable channel if DAC is off
    }
  }

  // NR13: Frequency Low
  int readNR13() => 0xFF; // Write-only register
  void writeNR13(int value) {
    nr13 = value;
    frequency = (nr14 & 0x07) << 8 | nr13;
    updateFrequencyTimer();
  }

  // NR14: Frequency High and Control
  int readNR14() => (nr14 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR14(int value) {
    bool lengthEnable = (value & 0x40) != 0;
    nr14 = value;

    frequency = (nr14 & 0x07) << 8 | nr13;
    updateFrequencyTimer();

    // CGB obscure behavior: Length counter extra clocking during trigger
    // Only clock length if next frame sequencer step would NOT clock length
    bool nextStepClocksLength = (frameSequencer & 1) == 0;
    if (!nextStepClocksLength && lengthEnable && !lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }

    // CGB behavior: If triggering with length enabled and length at max, decrement it
    if ((value & 0x80) != 0 && lengthEnabled && lengthCounter == 64) {
      lengthCounter = 63; // Set to 63, not 64-1
    }

    // If triggering with length 0, reload to maximum
    if ((value & 0x80) != 0 && lengthCounter == 0) {
      lengthCounter = 64;
      // Extra clocking if we're about to clock length in the next step
      if (lengthEnabled && nextStepClocksLength) {
        lengthCounter = 63;
      }
    }

    lengthEnabled = lengthEnable;

    if ((nr14 & 0x80) != 0) {
      trigger();
    }
  }

  // Trigger the channel (on write to NR14 with bit 7 set)
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
      volume = (nr12 >> 4) & 0x0F; // Initial volume from NR12 bits 4-7

      // Length counter handling
      if (lengthCounter == 0) {
        lengthCounter = 64; // Full length
        // Extra clocking if length enabled during length-clocking steps
        if (lengthEnabled && (frameSequencer & 1) == 0) {
          lengthCounter--;
          if (lengthCounter == 0) {
            enabled = false;
          }
        }
      }

      // Sweep initialization - KameBoyColor behavior
      shadowFrequency = frequency;
      sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;
      sweepEnabled = (sweepPeriod != 0) || (sweepShift != 0);
      sweepNegateModeUsed = false;

      // Per Pan Docs: "If the shift amount is non-zero, frequency calculation
      // and overflow check are performed immediately"
      if (sweepShift != 0) {
        int newFreq = calculateSweepFrequency();
        if (newFreq > 2047) {
          enabled = false; // Disable channel immediately on overflow
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

  // Update envelope - matches KameBoyColor exactly (lines 525-538)
  void updateEnvelope() {
    // KameBoyColor checks volume_pace != 0, not envelopePeriod
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
        volume &= 0x0F; // KameBoyColor line 537
      }
    }
  }

  // Update sweep (called by frame sequencer)
  void updateSweep() {
    if (sweepEnabled && sweepPeriod > 0) {
      sweepTimer--;
      if (sweepTimer <= 0) {
        sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;
        if (sweepShift != 0) {
          int newFrequency = calculateSweepFrequency();
          if (newFrequency <= 2047 && enabled) {
            // Update internal frequency and shadow frequency
            shadowFrequency = newFrequency & 0x7FF;
            frequency = shadowFrequency;
            updateFrequencyTimer();

            // Perform second calculation for overflow check
            int overflowCheck = calculateSweepFrequency();
            if (overflowCheck > 2047) {
              enabled = false;
            }
          } else if (newFrequency > 2047) {
            // First calculation overflowed, disable channel
            enabled = false;
          }
        }
      }
    }
  }

  // Calculate the new frequency for the sweep
  // Returns the calculated frequency, caller should check for overflow
  int calculateSweepFrequency() {
    int delta = shadowFrequency >> sweepShift;
    int newFrequency;

    if (sweepNegate) {
      newFrequency = shadowFrequency - delta;
      sweepNegateModeUsed = true; // Track that negate mode was used
    } else {
      newFrequency = shadowFrequency + delta;
    }

    return newFrequency; // Return raw calculated frequency (may exceed 11-bit range)
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
    // Reset all registers
    nr10 = 0;
    nr11 = 0;
    nr12 = 0;
    nr13 = 0;
    nr14 = 0;

    // Reset internal state
    frequency = 0;
    frequencyTimer = 0;
    dutyStep = 0;
    volume = 0;
    lengthCounter = 0;

    // Reset sweep state
    sweepTimer = 0;
    sweepPeriod = 0;
    sweepShift = 0;
    sweepNegate = false;
    sweepEnabled = false;
    shadowFrequency = 0;
    sweepNegateModeUsed = false;

    // Reset envelope state
    envelopeTimer = 0;
    envelopePeriod = 0;
    envelopeIncrease = false;

    // Reset control flags
    enabled = false;
    dacEnabled = false;
    lengthEnabled = false;
    dutyCycle = 0;
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
