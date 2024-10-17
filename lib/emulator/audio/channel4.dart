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
  int volume = 0;

  int envelopeVolume = 0;
  int envelopePeriod = 0;
  int envelopeCounter = 0;
  int envelopeSweep = 0;
  bool envelopeDirection = false;

  int noiseCycleLength = 0; // Calculated noise cycle length based on NR43

  int readNR41() => nrx1 | 0xFF;
  int readNR42() => nrx2;
  int readNR43() => nrx3;
  int readNR44() => nrx4 | 0xBF;

  /// NR41: Sound length (64 steps)
  void writeNR41(int value) {
    nrx1 = value;

    // Set length counter
    lengthCounter =
        64 - (value & 0x3F); // Extract lower 6 bits for sound length
  }

  /// NR42: Volume envelope
  void writeNR42(int value) {
    nrx2 = value;

    // Volume and envelope settings
    volume = (value >> 4) & 0x0F; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // Envelope direction
    envelopeSweep = value & 0x07; // Envelope sweep period

    if (envelopeSweep == 0) envelopeSweep = 8; // Treat 0 sweep period as 8
  }

  /// NR43: Polynomial counter (controls noise frequency and LFSR width)
  void writeNR43(int value) {
    nrx3 = value;

    // Extract and set the polynomial counter divisor (controls noise frequency)
    int divisorCode = value & 0x07; // Lower 3 bits control the divisor

    // Set the polynomial counter (frequency control)
    polynomialCounter = divisorCode == 0 ? 8 : divisorCode * 16;

    // LFSR width (15-bit or 7-bit)
    if ((value & 0x08) != 0) {
      lfsr &= 0x7F; // Use 7-bit mode
    } else {
      lfsr &= 0x7FFF; // Use full 15-bit mode
    }
  }

  /// NR44: Counter/consecutive and initial
  void writeNR44(int value) {
    nrx4 = value;

    if ((value & 0x80) != 0) {
      // Trigger the channel
      lengthCounter = 64;
      envelopeCounter = envelopeSweep;
      enabled = true;

      // Reset the LFSR
      lfsr = 0x7FFF;
    }

    // Set length enabled
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
    if (!enabled || volume == 0) return 0;

    // Generate noise based on the LFSR (Linear Feedback Shift Register)
    int feedback = (lfsr ^ (lfsr >> 1)) & 1;
    lfsr = (lfsr >> 1) | (feedback << 14);

    // Scale the noise output based on the volume
    return feedback == 0
        ? -volume * 2
        : volume * 2; // Double volume scaling for better output
  }

  void generateNoise() {
    int feedback = (lfsr ^ (lfsr >> 1)) & 1;
    lfsr = (lfsr >> 1) | (feedback << 14);
  }
}
