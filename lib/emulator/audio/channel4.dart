class Channel4 {
  int nrx1 = 0; // Sound Length
  int nrx2 = 0; // Volume Envelope
  int nrx3 = 0; // Polynomial Counter
  int nrx4 = 0; // Counter/Consecutive; Initial

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;
  int lfsr = 0x7FFF; // 15-bit LFSR starting state
  int polynomialCounter = 0; // Polynomial counter (NR43)

  int envelopeVolume = 0;
  int envelopePeriod = 0;
  int envelopeCounter = 0;
  bool envelopeDirection = false;

  int noiseCycleLength = 0; // Calculated noise cycle length based on NR43

  int readNR41() => nrx1 | 0xFF;
  int readNR42() => nrx2;
  int readNR43() => nrx3;
  int readNR44() => nrx4 | 0xBF;

  /// NR41: Sound length (64 steps)
  void writeNR41(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // Set the length of noise playback

    // Enable the channel when sound length is configured
    enabled = true;
  }

  /// NR42: Volume envelope
  void writeNR42(int value) {
    nrx2 = value;
    envelopeVolume = (value >> 4) & 0xF; // Initial volume (4 bits)
    envelopeDirection =
        (value & 0x08) != 0; // Envelope direction (1: increase, 0: decrease)
    envelopePeriod = value & 0x07; // Envelope sweep time (3 bits)

    if (envelopePeriod == 0) {
      envelopePeriod = 8; // When set to 0, behaves as 8 steps
    }

    envelopeCounter = envelopePeriod; // Reset envelope timer
  }

  /// NR43: Polynomial counter (controls noise frequency and LFSR width)
  void writeNR43(int value) {
    nrx3 = value;

    int shiftClockFreq =
        (value >> 4) & 0xF; // Upper 4 bits for shift clock frequency
    int divisorCode = value & 0x7; // Lower 3 bits control the divisor

    int divisor = divisorCode == 0 ? 8 : divisorCode * 16;

    // Set noise cycle length based on the polynomial counter and shift clock frequency
    noiseCycleLength = divisor << shiftClockFreq;

    // LFSR width control: 0 for 15-bit LFSR, 1 for 7-bit LFSR
    bool lfsrWidth = (value & 0x08) != 0;

    if (lfsrWidth) {
      lfsr &= 0x7F; // 7-bit LFSR mode (use only the lower 7 bits)
    } else {
      lfsr &= 0x7FFF; // 15-bit LFSR mode (use the full 15-bit value)
    }
  }

  /// NR44: Counter/consecutive and initial
  void writeNR44(int value) {
    nrx4 = value;

    if ((value & 0x80) != 0) {
      // Trigger the noise channel
      lengthCounter = 64;
      envelopeCounter = envelopePeriod;
      enabled = true;

      // Reset the LFSR
      lfsr = 0x7FFF;
    }

    // Enable the length counter if bit 6 is set
    lengthEnabled = (value & 0x40) != 0;
  }

  void reset() {
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
    lfsr = 0x7FFF; // Reset the LFSR
  }

  void tick(int delta) {
    if (!enabled) return;

    // Noise generation based on the polynomial counter logic
    polynomialCounter -= delta;
    if (polynomialCounter <= 0) {
      // Reset the polynomial counter
      polynomialCounter = noiseCycleLength;

      // Perform the LFSR shift and noise generation
      generateNoise();
    }

    // Handle envelope updates
    updateEnvelope();

    // Handle length counter logic
    updateLengthCounter();
  }

  // Envelope Update
  void updateEnvelope() {
    if (envelopePeriod > 0) {
      envelopeCounter--;
      if (envelopeCounter == 0) {
        envelopeCounter = envelopePeriod; // Reset envelope counter
        if (envelopeDirection && envelopeVolume < 15) {
          envelopeVolume++; // Increase volume
        } else if (!envelopeDirection && envelopeVolume > 0) {
          envelopeVolume--; // Decrease volume
        }
      }
    }
  }

  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }

  int getOutput() {
    if (!enabled) return 0;
    return (lfsr & 1) == 1 ? envelopeVolume : 0;
  }

  void generateNoise() {
    int feedback = (lfsr ^ (lfsr >> 1)) & 1;
    lfsr = (lfsr >> 1) | (feedback << 14);
  }
}
