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
    nr10 = value;
    sweepPeriod = (nr10 >> 4) & 0x07;
    sweepNegate = (nr10 & 0x08) != 0;
    sweepShift = nr10 & 0x07;
    sweepEnabled = sweepPeriod != 0 || sweepShift != 0;
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
  int readNR12() => nr12;
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
    bool wasLengthEnabled = lengthEnabled;
    nr14 = value;
    lengthEnabled = (nr14 & 0x40) != 0;
    frequency = (nr14 & 0x07) << 8 | nr13;
    updateFrequencyTimer();
    
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
      // Reset frequency timer with initial period
      frequencyTimer = 4 * (2048 - frequency);

      // Pan Docs: "duty step is reset to 0" (starts outputting low)
      dutyStep = 0;

      // Reset envelope
      envelopeTimer = envelopePeriod;
      volume = (nr12 >> 4) & 0x0F; // Initial volume from NR12 bits 4-7

      // Length counter handling
      if (lengthCounter == 0) {
        lengthCounter = 64; // Full length
        // Extra clocking if frame sequencer is about to clock length
        if (lengthEnabled && (frameSequencer & 1) == 0) {
          lengthCounter--;
          if (lengthCounter == 0) {
            enabled = false;
          }
        }
      }

      // Sweep initialization
      shadowFrequency = frequency;
      sweepTimer = sweepPeriod > 0 ? sweepPeriod : 8;
      sweepEnabled = (sweepPeriod != 0) || (sweepShift != 0);

      // Initial frequency calculation and overflow check
      if (sweepShift != 0) {
        int newFreq = calculateSweepFrequency();
        if (newFreq > 2047) {
          enabled = false; // Disable if overflow
        }
      }
    }
  }

  // Update the frequency timer based on the current frequency
  void updateFrequencyTimer() {
    frequencyTimer = (2048 - frequency) * 4;
    if (frequencyTimer <= 0) frequencyTimer = 4; // Ensure minimum period
  }

  // Update method called every CPU cycle - cycle accurate per Pan Docs
  void tick(int cycles) {
    if (!enabled) return;

    // Frequency timer decrements every CPU cycle
    // Period = 4 * (2048 - frequency) CPU cycles
    // Duty step advances when timer reaches 0
    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      // Calculate the reload period
      int period = 4 * (2048 - frequency);
      if (period <= 0) period = 4; // Minimum period to prevent locks

      // Reload timer
      frequencyTimer += period;

      // Advance duty step (Pan Docs: "duty step counter advances")
      dutyStep = (dutyStep + 1) % 8;
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

  // Update envelope (called by frame sequencer)
  void updateEnvelope() {
    if (envelopePeriod > 0 && enabled) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
        if (envelopeIncrease && volume < 15) {
          volume++;
        } else if (!envelopeIncrease && volume > 0) {
          volume--;
        }

        // Disable envelope if volume reaches boundary
        if (volume == 0 || volume == 15) {
          envelopeTimer = 0;
        }
      }
    }
  }

  // Update sweep (called by frame sequencer)
  void updateSweep() {
    if (sweepEnabled && sweepPeriod > 0) {
      sweepTimer--;
      if (sweepTimer <= 0) {
        sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;
        int newFrequency = calculateSweepFrequency();
        if (newFrequency <= 2047 && sweepShift != 0 && enabled) {
          frequency = newFrequency;
          shadowFrequency = newFrequency;
          updateFrequencyTimer();
          calculateSweepFrequency(); // Second calculation for overflow check
        }
      }
    }
  }

  // Calculate the new frequency for the sweep
  int calculateSweepFrequency() {
    int delta = shadowFrequency >> sweepShift;
    int newFrequency =
        sweepNegate ? shadowFrequency - delta : shadowFrequency + delta;

    // Check for overflow and disable if out of range
    if (newFrequency > 2047) {
      enabled = false;
      return newFrequency & 0x7FF; // Return masked value even if disabled
    }
    
    return newFrequency & 0x7FF; // Ensure 11-bit frequency
  }

  // Get the output sample for the current state
  // Returns digital value (0-15) that will be converted by DAC
  int getOutput() {
    // If channel or DAC is disabled, output 0
    if (!enabled || !dacEnabled) return 0;

    // Get current duty pattern bit
    int dutyBit = dutyPatterns[dutyCycle][dutyStep];

    // Output volume when duty is high, 0 when low
    // This produces the correct square wave with proper amplitude
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

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }
}
