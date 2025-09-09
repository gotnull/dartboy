class Channel4 {
  // Registers
  int nr41 = 0; // Sound Length (NR41)
  int nr42 = 0; // Volume Envelope (NR42)
  int nr43 = 0; // Polynomial Counter (NR43)
  int nr44 = 0; // Counter/Consecutive; Initial (NR44)

  // Internal variables
  int frequencyTimer = 0; // Frequency timer
  int lengthCounter = 0; // Length counter
  int volume = 0; // Current volume (0-15)
  int envelopeTimer = 0; // Envelope timer
  int envelopePeriod = 0;
  bool envelopeIncrease = false; // Envelope direction
  int lfsr = 0x7FFF; // 15-bit LFSR starting value
  bool widthMode7 = false; // LFSR width mode (15-bit or 7-bit)

  // Channel enabled flag
  bool enabled = false;

  // Length counter enabled flag
  bool lengthEnabled = false;

  // DAC enabled flag (determined by NR42)
  bool dacEnabled = false;

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
  int readNR42() => nr42;
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
  int readNR43() => nr43;
  void writeNR43(int value) {
    nr43 = value;
    updateFrequencyTimer();
    widthMode7 = (nr43 & 0x08) != 0;
  }

  // NR44: Counter/Consecutive; Initial
  int readNR44() => 0xFF; // Write-only register
  void writeNR44(int value) {
    bool wasLengthEnabled = lengthEnabled;
    nr44 = value;
    lengthEnabled = (nr44 & 0x40) != 0;
    if ((nr44 & 0x80) != 0) {
      trigger();
    }
    if (!wasLengthEnabled &&
        lengthEnabled &&
        lengthCounter == 0 &&
        frameSequencer % 2 != 0) {
      lengthCounter = 64;
    }
  }

  // Trigger the channel (on write to NR44 with bit 7 set)
  void trigger() {
    enabled = dacEnabled;
    frequencyTimer = getFrequencyTimerPeriod();
    envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
    volume = (nr42 >> 4) & 0x0F;
    lengthCounter = lengthCounter == 0 ? 64 : lengthCounter;
    lfsr = 0x7FFF; // Reset LFSR to all ones
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
  }

  // Update method called every CPU cycle
  void tick(int cycles) {
    if (!enabled) return;

    // Frequency timer
    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      frequencyTimer += getFrequencyTimerPeriod();
      clockLFSR();
    }
  }

  // Clock the LFSR
  void clockLFSR() {
    int bit = ((lfsr & 1) ^ ((lfsr >> 1) & 1));
    lfsr = (lfsr >> 1) | (bit << 14);
    if (widthMode7) {
      // Set bit 6 with the XOR result
      lfsr = (lfsr & ~(1 << 6)) | (bit << 6);
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
    if (envelopePeriod > 0) {
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

  // Get the output sample for the current state
  int getOutput() {
    if (!enabled || !dacEnabled) return 0;
    int output = (~lfsr) & 1;
    int sample = output == 0 ? -volume : volume;
    return sample;
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
    widthMode7 = false;
  }

  // Frame sequencer reference (needs to be set from Audio class)
  int frameSequencer = 0;

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }
}
