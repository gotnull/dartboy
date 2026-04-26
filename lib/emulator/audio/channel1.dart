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
  bool sweepNegateModeUsed =
      false; // Tracks if negate mode has been used (obscure behavior)

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
    [0, 0, 0, 0, 0, 0, 0, 1], // 12.5%
    [0, 0, 0, 0, 0, 0, 1, 1], // 25%
    [0, 0, 0, 0, 1, 1, 1, 1], // 50%
    [1, 1, 1, 1, 1, 1, 0, 0], // 75%
  ];

  // Duty cycle index (0-3)
  int dutyCycle = 0;

  // Constructor
  Channel1();

  // NR10: Sweep Register
  int readNR10() =>
      (nr10 & 0x7F) | 0x80; // Only bits 0-6 writable, bit 7 always 1
  void writeNR10(int value) {
    bool oldSweepNegate = sweepNegate;
    nr10 = value;
    sweepPeriod = (nr10 >> 4) & 0x07;
    sweepNegate = (nr10 & 0x08) != 0;
    sweepShift = nr10 & 0x07;

    // Pan Docs: clearing the sweep negate bit after at least one sweep
    // calculation has been made in negate mode since the last trigger
    // immediately disables the channel.
    if (sweepNegateModeUsed && oldSweepNegate && !sweepNegate) {
      enabled = false;
    }
    // sweepEnabled is set on trigger only, not on NR10 writes. The internal
    // sweep timer keeps running across NR10 writes; it only reloads when it
    // reaches zero.
  }

  // NR11: Sound Length / Waveform Duty
  int readNR11() =>
      (nr11 & 0xC0) | 0x3F; // Only bits 6-7 readable, bits 0-5 always 1
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
    // Volume is NOT set here - only loaded from NR12 on trigger
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
    // Only update the *period*, not the running countdown. Real hardware
    // keeps the current frequency timer counting down and reloads it with
    // the new period the next time it expires; resetting the countdown on
    // every NR13/NR14 write would make vibrato and pitch slides sound
    // choppy because every register write would restart the duty cycle.
    frequency = (nr14 & 0x07) << 8 | nr13;
  }

  // NR14: Frequency High and Control
  int readNR14() =>
      (nr14 & 0x40) | 0xBF; // Only bit 6 readable, others read as 1
  void writeNR14(int value) {
    bool newLengthEnable = (value & 0x40) != 0;
    bool triggering = (value & 0x80) != 0;
    nr14 = value;

    // See note in writeNR13: only the period changes; the timer reload
    // happens naturally when the current countdown reaches zero. Triggering
    // (handled below) is what restarts the timer from scratch.
    frequency = (nr14 & 0x07) << 8 | nr13;

    // Pan Docs extra-length-clock quirk: writing NRx4 with length transitioning
    // from disabled→enabled, on a frame-sequencer step whose next step does
    // NOT clock the length counter (i.e. the current step is even: 0,2,4,6),
    // and length > 0, decrements length. If this hits zero with no trigger,
    // the channel is disabled.
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

  // Trigger the channel (on write to NR14 with bit 7 set).
  // All trigger side-effects (timer reload, length reload, sweep init) occur
  // even if the DAC is off; only the channel-enabled flag depends on the DAC.
  void trigger() {
    // Reset frequency timer.
    frequencyTimer = 4 * (2048 - frequency);
    dutyStep = 0;

    // Reload envelope timer (period 0 treated as 8) and volume from NR12.
    envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
    volume = (nr12 >> 4) & 0x0F;

    // Length reload if zero, with the trigger-on-doesn't-clock-step quirk.
    if (lengthCounter == 0) {
      lengthCounter = 64;
      bool nextStepDoesntClockLength = (frameSequencer & 1) == 0;
      if (lengthEnabled && nextStepDoesntClockLength) {
        lengthCounter = 63;
      }
    }

    // Sweep initialization.
    shadowFrequency = frequency;
    sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;
    sweepEnabled = (sweepPeriod != 0) || (sweepShift != 0);
    sweepNegateModeUsed = false;

    // Channel becomes enabled iff DAC is on.
    enabled = dacEnabled;

    // Pan Docs: if shift is non-zero, perform an immediate sweep frequency
    // calculation and overflow check on trigger.
    if (sweepShift != 0) {
      int newFreq = calculateSweepFrequency();
      if (newFreq > 2047) {
        enabled = false;
      }
    }
  }

  // Update frequency timer - back to working formula
  void updateFrequencyTimer() {
    frequencyTimer = 4 * (2048 - frequency);
    if (frequencyTimer <= 0) frequencyTimer = 4;
  }

  /// Running accumulator: sum of (instantaneous-output × cycles-in-that-state)
  /// since the last call to [getAveragedOutput]. Used to band-limit the
  /// channel by emitting the time-weighted average rather than a snapshot,
  /// which is what produces the "crunchy" aliasing on high-pitched notes.
  double _outAcc = 0.0;
  int _cycAcc = 0;

  // Frequency timer - 0-based duty step, counts down. Splits each tick into
  // sub-segments at every duty-step transition and accumulates the
  // time-weighted output over each segment.
  void tick(int cycles) {
    if (!enabled) {
      _cycAcc += cycles;
      return;
    }

    while (cycles > 0) {
      final int dutyBit = dutyPatterns[dutyCycle][dutyStep];
      final int instOut = dutyBit == 1 ? volume : 0;

      // The current duty step lasts until [frequencyTimer] runs out;
      // anything past that gets a fresh duty bit and a fresh period.
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

  /// Time-weighted average output (0.0..15.0) over the cycles ticked since
  /// the last call. Returning a fractional value preserves the signal's
  /// energy at frequencies above Nyquist instead of folding them back as
  /// audible aliasing.
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

  void updateSweep() {
    if (!enabled) return;

    sweepTimer--;
    if (sweepTimer > 0) return;

    // Reload timer. Period 0 is treated as 8 by hardware.
    sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;

    // Calculation only runs when the internal enabled flag is set
    // AND the period (as written in NR10) is non-zero.
    if (!sweepEnabled || sweepPeriod == 0) return;

    int newFrequency = calculateSweepFrequency();

    // First overflow check - applies regardless of shift.
    if (newFrequency > 2047) {
      enabled = false;
      return;
    }

    // Writeback only when shift is non-zero.
    if (sweepShift != 0) {
      shadowFrequency = newFrequency & 0x7FF;
      frequency = shadowFrequency;
      // Reflect the updated frequency in NR13/NR14 (low 8 bits and low 3 bits).
      nr13 = frequency & 0xFF;
      nr14 = (nr14 & 0xF8) | ((frequency >> 8) & 0x07);
      updateFrequencyTimer();

      // Second overflow check (no writeback).
      int overflowCheck = calculateSweepFrequency();
      if (overflowCheck > 2047) {
        enabled = false;
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

    // 0-based duty step index (0-7)
    int dutyBit = dutyPatterns[dutyCycle][dutyStep];

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
