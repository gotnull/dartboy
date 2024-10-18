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
  int sampleBuffer = 0; // Holds the current waveform sample
  int envelopeSweep = 0;

  int dutyCycleIndex = 0; // Index for duty cycle
  List<int> dutyCycles = [0x01, 0x81, 0xC7, 0x7E];

  // NR21: Sound Length/Wave Duty (NR21)
  int readNR21() => nrx1 | 0x3F;
  void writeNR21(int value) {
    nrx1 = value;

    // Set length counter
    lengthCounter =
        64 - (value & 0x3F); // Extract lower 6 bits for sound length

    // Duty cycle: 00, 01, 10, 11 map to 12.5%, 25%, 50%, 75%
    dutyCycleIndex = (value >> 6) & 0x03;
  }

  // NR22: Volume Envelope (NR22)
  int readNR22() => nrx2;
  void writeNR22(int value) {
    nrx2 = value;

    // Volume and envelope settings
    volume = (value >> 4) & 0x0F; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // Envelope direction
    envelopeSweep = value & 0x07; // Envelope sweep period

    if (envelopeSweep == 0) envelopeSweep = 8; // Treat 0 sweep period as 8
  }

  // NR23: Frequency low (NR23)
  int readNR23() => nrx3 | 0xFF;
  void writeNR23(int value) {
    nrx3 = value;

    // Lower 8 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | value;
  }

  // NR24: Frequency high + Control (NR24)
  int readNR24() => nrx4 | 0xBF;
  void writeNR24(int value) {
    nrx4 = value;

    // Higher 3 bits of frequency
    frequency = (nrx4 & 0x07) << 8 | nrx3;

    if ((value & 0x80) != 0) {
      // Trigger the channel
      enabled = true;
      waveformPhase = 0;

      // Reload envelope
      envelopeTimer = envelopeSweep;
      volume = (nrx2 >> 4) & 0xF;

      // Set cycle length
      cycleLength = (2048 - frequency) * 4;
    }
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
        envelopeTimer = envelopeSweep; // Reload the timer with envelopeSweep
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
    if (!enabled || volume == 0) return 0;

    // Ensure cycleLength is not too small to avoid division by zero
    if (cycleLength < 8) {
      print(
          "Error: cycleLength is too small ($cycleLength), returning 0 output.");
      return 0;
    }

    // Duty cycle determines the high/low pattern of the square wave
    int dutyPattern = [0x01, 0x81, 0xC7, 0x7E][dutyCycleIndex];

    // Determine if we're in the high phase of the waveform
    bool isHighPhase =
        (dutyPattern & (1 << (waveformPhase ~/ (cycleLength ~/ 8)))) != 0;

    // Return volume scaled by whether it's in the high or low phase
    return isHighPhase ? volume * 2 : -volume * 2;
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
