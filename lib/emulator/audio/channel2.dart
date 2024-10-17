class Channel2 {
  int nrx1 = 0; // Sound Length/Wave Duty (NR21)
  int nrx2 = 0; // Volume Envelope (NR22)
  int nrx3 = 0; // Frequency low (NR23)
  int nrx4 = 0; // Frequency high + Control (NR24)

  int frequency = 0; // Current frequency
  int waveformPhase = 0; // Track the current phase of the waveform
  int cycleLength = 0; // Frequency timer period
  int envelopeTimer = 0; // Timer for the volume envelope

  bool enabled = false; // Whether the channel is currently enabled
  bool envelopeDirection = false; // Whether the envelope increases or decreases
  bool lengthEnabled = false; // Length counter enabled flag

  int lengthCounter = 0; // Length counter
  int volume = 0; // Current volume

  int dutyCycleIndex = 0; // Index for duty cycle
  List<int> dutyCycles = [0x01, 0x81, 0xC7, 0x7E];

  // NR21: Sound Length/Wave Duty (NR21)
  int readNR21() => nrx1 | 0x3F;
  void writeNR21(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // 64-step length counter
    dutyCycleIndex = (value >> 6) & 0x03; // Duty cycle index (2 bits)
  }

  // NR22: Volume Envelope (NR22)
  int readNR22() => nrx2;
  void writeNR22(int value) {
    nrx2 = value;

    volume = value >> 4 & 0x0F; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // 1 = increase, 0 = decrease
    int envelopePeriod = value & 0x07; // Number of envelope steps
    if (envelopePeriod == 0) {
      envelopePeriod = 8; // Period of 0 is treated as 8
    }
    envelopeTimer = envelopePeriod;
  }

  // NR23: Frequency low (NR23)
  int readNR23() => nrx3 | 0xFF;
  void writeNR23(int value) {
    nrx3 = value;
    frequency = (nrx4 & 0x07) << 8 | nrx3; // Combine low and high frequency
    cycleLength =
        (2048 - frequency) * 4; // Update cycle length based on frequency
  }

  // NR24: Frequency high + Control (NR24)
  int readNR24() => nrx4 | 0xBF;
  void writeNR24(int value) {
    nrx4 = value;
    frequency =
        (nrx4 & 0x07) << 8 | nrx3; // Combine NR23 and NR24 for frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length

    if (value & 0x80 != 0) {
      trigger(); // Trigger the channel when bit 7 is set
    }
    lengthEnabled = (value & 0x40) != 0; // Length counter enable (bit 6)
  }

  // Trigger the channel (reset length counter, envelope, and frequency)
  void trigger() {
    enabled = true;
    waveformPhase = 0;
    lengthCounter =
        lengthCounter == 0 ? 64 : lengthCounter; // Reload length if zero
    envelopeTimer = envelopeTimer == 0 ? 8 : envelopeTimer; // Reload envelope
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

    // Ensure division results in an integer
    int phaseIndex =
        (waveformPhase ~/ (cycleLength ~/ 8)); // Use integer division
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
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
    envelopeDirection = false;
    lengthEnabled = false;
    volume = 0;
    lengthCounter = 0;
    cycleLength = 0;
    waveformPhase = 0;
  }
}
