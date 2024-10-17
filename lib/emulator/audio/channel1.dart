class Channel1 {
  int nrx0 = 0; // Sweep (NR10)
  int nrx1 = 0; // Sound Length/Wave Duty (NR11)
  int nrx2 = 0; // Volume Envelope (NR12)
  int nrx3 = 0; // Frequency low (NR13)
  int nrx4 = 0; // Frequency high + Control (NR14)

  int frequency = 0; // Current frequency
  int waveformPhase = 0; // Track the current phase of the waveform
  int cycleLength = 0; // Frequency timer period
  int sweepTimer = 0; // Timer for the frequency sweep
  int envelopeTimer = 0; // Timer for the volume envelope

  bool enabled = false; // Whether the channel is currently enabled
  bool sweepEnabled = false; // Sweep enabled flag
  bool envelopeDirection = false; // Whether the envelope increases or decreases
  bool lengthEnabled = false; // Length counter enabled flag
  bool sweepDirection = false; // Sweep direction (true for decreasing)

  int lengthCounter = 0; // Length counter
  int volume = 0; // Current volume
  int sweepShift = 0; // Frequency sweep shift
  int sweepPeriod = 0; // Sweep time period
  int initialFrequency = 0; // The initial frequency at trigger

  int dutyCycleIndex = 0; // Index for duty cycle
  List<int> dutyCycles = [0x01, 0x81, 0xC7, 0x7E];

  // NR10: Sweep (NR10)
  int readNR10() => nrx0 | 0x80;
  void writeNR10(int value) {
    nrx0 = value;

    sweepPeriod = (value >> 4) & 0x7; // Sweep time in steps
    sweepDirection = (value & 0x08) != 0; // 1 = decrease, 0 = increase
    sweepShift = value & 0x07; // Frequency shift

    sweepEnabled = sweepShift > 0 || sweepDirection;
  }

  // NR11: Sound Length/Wave Duty (NR11)
  int readNR11() => nrx1 | 0x3F;
  void writeNR11(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // 64-step length counter
    dutyCycleIndex = (value >> 6) & 0x03; // Duty cycle index (2 bits)
  }

  // NR12: Volume Envelope (NR12)
  int readNR12() => nrx2;
  void writeNR12(int value) {
    nrx2 = value;

    volume = value >> 4 & 0x0F; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // 1 = increase, 0 = decrease
    int envelopePeriod = value & 0x07; // Number of envelope steps
    if (envelopePeriod == 0) {
      envelopePeriod = 8; // Period of 0 is treated as 8
    }
    envelopeTimer = envelopePeriod;
  }

  // NR13: Frequency low (NR13)
  int readNR13() => nrx3 | 0xFF;
  void writeNR13(int value) {
    nrx3 = value;
    frequency = (nrx4 & 0x07) << 8 | nrx3; // Combine low and high frequency
    cycleLength =
        (2048 - frequency) * 4; // Update cycle length based on frequency
  }

  // NR14: Frequency high + Control (NR14)
  int readNR14() => nrx4 | 0xBF;
  void writeNR14(int value) {
    nrx4 = value;
    frequency =
        (nrx4 & 0x07) << 8 | nrx3; // Combine NR13 and NR14 for frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length

    if (value & 0x80 != 0) {
      trigger(); // Trigger the channel when bit 7 is set
    }
    lengthEnabled = (value & 0x40) != 0; // Length counter enable (bit 6)
  }

  // Trigger the channel (reset length counter, envelope, and sweep)
  void trigger() {
    enabled = true;
    waveformPhase = 0;
    lengthCounter =
        lengthCounter == 0 ? 64 : lengthCounter; // Reload length if zero
    envelopeTimer = envelopeTimer == 0 ? 8 : envelopeTimer; // Reload envelope

    // Reload sweep timer
    if (sweepPeriod != 0 && sweepEnabled) {
      sweepTimer = sweepPeriod;
    } else {
      sweepTimer = 8;
    }
    initialFrequency = frequency;
  }

  // Length counter logic
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Disable the channel when the counter reaches zero
      }
    }
  }

  // Sweep logic (adjust frequency over time)
  void updateSweep() {
    if (sweepEnabled && sweepPeriod > 0) {
      sweepTimer--;
      if (sweepTimer == 0) {
        sweepTimer = sweepPeriod;

        int newFrequency = calculateSweep();
        if (newFrequency > 2047) {
          enabled = false; // Disable if frequency exceeds maximum
        } else if (sweepShift > 0) {
          frequency = newFrequency;
          cycleLength = (2048 - frequency) * 4;
        }
      }
    }
  }

  // Calculate the next frequency based on the sweep shift and direction
  int calculateSweep() {
    int shiftedFrequency = frequency >> sweepShift;
    if (sweepDirection) {
      return frequency - shiftedFrequency; // Decrease frequency
    } else {
      return frequency + shiftedFrequency; // Increase frequency
    }
  }

  // Volume envelope logic
  void updateEnvelope() {
    if (envelopeTimer > 0) {
      envelopeTimer--;
      if (envelopeTimer == 0) {
        envelopeTimer = nrx2 & 0x07; // Reload the timer
        if (envelopeTimer == 0) {
          envelopeTimer = 8; // Period of 0 is treated as 8
        }
        if (envelopeDirection) {
          if (volume < 15) {
            volume++; // Increase volume
          }
        } else {
          if (volume > 0) {
            volume--; // Decrease volume
          }
        }
      }
    }
  }

  // Generate the square wave output based on the duty cycle and current phase
  int getOutput() {
    if (!enabled || volume == 0) {
      return 0; // Return 0 if the channel is disabled or muted
    }

    // Calculate which phase of the waveform we're in
    int dutyPattern = dutyCycles[dutyCycleIndex];

    // Ensure integer division
    int phaseIndex =
        waveformPhase ~/ (cycleLength ~/ 8); // Use integer division
    bool isHighPhase = (dutyPattern & (1 << phaseIndex)) != 0;

    // Return volume based on whether we are in the high or low phase
    return isHighPhase ? volume : -volume;
  }

  // Tick the channel (advance the waveform and handle timing)
  void tick(int delta) {
    if (!enabled) return;

    // Update the waveform phase based on CPU cycles
    waveformPhase += delta;
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0; // Reset phase at the end of the waveform cycle
    }
  }

  // Reset the channel state
  void reset() {
    nrx0 = 0;
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
    sweepEnabled = false;
    sweepDirection = false;
    envelopeDirection = false;
    lengthEnabled = false;
    volume = 0;
    lengthCounter = 0;
    cycleLength = 0;
    waveformPhase = 0;
    sweepShift = 0;
    sweepPeriod = 0;
    initialFrequency = 0;
  }
}
