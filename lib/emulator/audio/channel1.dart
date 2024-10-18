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
  int envelopeSweep = 0;

  bool enabled = false; // Whether the channel is currently enabled
  bool sweepEnabled = false; // Sweep enabled flag
  bool envelopeDirection = false; // Whether the envelope increases or decreases
  bool lengthEnabled = false; // Length counter enabled flag
  bool sweepDirection = false; // Sweep direction (true for decreasing)
  int envelopePeriod = 0;

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

    // If sweep time is 0, treat it as 8 according to hardware
    if (sweepPeriod == 0) sweepPeriod = 8;

    // Enable sweep if the shift is non-zero
    sweepEnabled = (sweepShift > 0);

    print("Sweep enabled: $sweepEnabled, sweepShift: $sweepShift");
  }

  // NR11: Sound Length/Wave Duty (NR11)
  int readNR11() => nrx1 | 0x3F;
  void writeNR11(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // 64-step length counter

    // Duty cycle: 00, 01, 10, 11 map to 12.5%, 25%, 50%, 75%
    dutyCycleIndex = (value >> 6) & 0x03;
  }

  // NR12: Volume Envelope (NR12)
  int readNR12() => nrx2;
  void writeNR12(int value) {
    nrx2 = value;

    // Volume and envelope settings
    volume = (value >> 4) & 0x0F; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // Envelope direction
    envelopePeriod = value & 0x07; // Envelope sweep period

    // Treat envelope sweep of 0 as 8, as per hardware behavior
    if (envelopePeriod == 0) envelopePeriod = 8;
  }

  // NR13: Frequency low (NR13)
  int readNR13() => nrx3 | 0xFF;
  void writeNR13(int value) {
    nrx3 = value;

    // Lower 8 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | value;

    // Recalculate cycle length based on frequency
    if (frequency != 0) {
      cycleLength = (2048 - frequency) * 4;
    } else {
      cycleLength =
          2048 * 4; // Set a default cycle length to avoid too-small values
    }
  }

  // NR14: Frequency high + Control (NR14)
  int readNR14() => nrx4 | 0xBF;
  void writeNR14(int value) {
    nrx4 = value;

    // Higher 3 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | nrx3;

    if ((value & 0x80) != 0) {
      // Trigger the channel
      enabled = true;
      waveformPhase = 0;

      // Re-enable the sweep if the shift and period are valid
      if (sweepShift > 0) {
        sweepEnabled = true;
        print("Sweep enabled on channel trigger.");
      }

      // Reload the sweep timer
      sweepTimer = (sweepPeriod != 0 && sweepEnabled) ? sweepPeriod : 8;
    }
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
    if (sweepEnabled && sweepPeriod > 0 && sweepShift > 0) {
      // Add check for valid period and shift
      sweepTimer--;
      if (sweepTimer == 0) {
        sweepTimer = sweepPeriod;

        int newFrequency = calculateSweep();
        if (newFrequency > 2047) {
          enabled = false; // Disable if frequency exceeds maximum
          sweepEnabled = false; // Disable sweep if frequency exceeds limit
          print("Channel1 disabled due to frequency > 0x7FF.");
        } else {
          frequency = newFrequency;
          cycleLength = (2048 - frequency) * 4;
          print("Channel1 frequency updated: $frequency");
        }
      }
    }
  }

  // Calculate the next frequency based on the sweep shift and direction
  int calculateSweep() {
    int shiftedFrequency = frequency >> sweepShift;
    int result = sweepDirection
        ? frequency - shiftedFrequency
        : frequency + shiftedFrequency;

    print(
        "Sweep calculation: frequency = $frequency, shifted = $shiftedFrequency, result = $result");
    return result;
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
  // Generate the square wave output based on the duty cycle and current phase
  int getOutput() {
    if (!enabled || volume == 0) return 0;

    // Debugging output to see the values
    // print("Waveform Phase: $waveformPhase, Cycle Length: $cycleLength");

    // Ensure cycleLength is not too small to avoid division by zero
    if (cycleLength < 8) {
      print(
          "Error: cycleLength is too small ($cycleLength), returning 0 output.");
      return 0; // Prevent division by zero with very small cycle length
    }

    // Use the dutyCycleIndex set in writeNR11 to determine the duty cycle pattern
    int dutyPattern = [0x01, 0x81, 0xC7, 0x7E][dutyCycleIndex]; // Duty patterns

    // Determine if we're in the high phase of the waveform based on the duty cycle
    bool isHighPhase =
        (dutyPattern & (1 << (waveformPhase ~/ (cycleLength ~/ 8)))) != 0;

    // Return volume scaled by whether it's in the high or low phase
    return isHighPhase
        ? volume * 2
        : -volume * 2; // Double the volume scaling for better output
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
