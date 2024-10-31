class Channel2 {
  // Registers
  int nr21 = 0; // Sound Length/Wave Duty (NR21)
  int nr22 = 0; // Volume Envelope (NR22)
  int nr23 = 0; // Frequency low (NR23)
  int nr24 = 0; // Frequency high + Control (NR24)

  // Internal variables
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer
  int waveformIndex = 0; // Current position in waveform (0-7)
  int envelopeTimer = 0; // Timer for the volume envelope
  int lengthCounter = 0; // Length counter
  int volume = 0; // Current volume (0-15)

  // Envelope variables
  bool envelopeIncrease = false; // Envelope direction (true for increase)
  int envelopePeriod = 0;

  // Length counter enabled flag
  bool lengthEnabled = false;

  // Channel enabled flag
  bool enabled = false;

  // Duty cycle variables
  int dutyCycle = 0; // Duty cycle index (0-3)
  static const List<List<int>> dutyPatterns = [
    [0, 1, 0, 0, 0, 0, 0, 0], // 12.5%
    [0, 1, 1, 0, 0, 0, 0, 0], // 25%
    [0, 1, 1, 1, 1, 0, 0, 0], // 50%
    [1, 0, 0, 0, 0, 1, 1, 1], // 75%
  ];

  // DAC enabled flag (determined by NR22)
  bool dacEnabled = false;

  // Constructor
  Channel2();

  // NR21: Sound Length / Waveform Duty
  int readNR21() => nr21 | 0x3F; // Bits 0-5 are unused/read-only
  void writeNR21(int value) {
    nr21 = value;
    dutyCycle = (nr21 >> 6) & 0x03;
    int lengthData = nr21 & 0x3F;
    lengthCounter = 64 - lengthData;
  }

  // NR22: Volume Envelope
  int readNR22() => nr22;
  void writeNR22(int value) {
    nr22 = value;
    volume = (nr22 >> 4) & 0x0F;
    envelopeIncrease = (nr22 & 0x08) != 0;
    envelopePeriod = nr22 & 0x07;
    dacEnabled = (nr22 & 0xF8) != 0;
    if (!dacEnabled) {
      enabled = false;
    }
  }

  // NR23: Frequency Low
  int readNR23() => 0xFF; // Write-only register
  void writeNR23(int value) {
    nr23 = value;
    frequency = (nr24 & 0x07) << 8 | nr23;
    updateFrequencyTimer();
  }

  // NR24: Frequency High and Control
  int readNR24() => nr24 | 0xBF; // Bits 6-7 are unused/read-only
  void writeNR24(int value) {
    bool wasLengthEnabled = lengthEnabled;
    nr24 = value;
    lengthEnabled = (nr24 & 0x40) != 0;
    frequency = (nr24 & 0x07) << 8 | nr23;
    updateFrequencyTimer();
    if ((nr24 & 0x80) != 0) {
      trigger();
    }
    if (!wasLengthEnabled &&
        lengthEnabled &&
        lengthCounter == 0 &&
        frameSequencer == 0) {
      lengthCounter = 63;
    }
  }

  // Trigger the channel (on write to NR24 with bit 7 set)
  void trigger() {
    enabled = dacEnabled;
    frequencyTimer = (2048 - frequency) * 4;
    waveformIndex = 0;
    envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
    volume = (nr22 >> 4) & 0x0F;
    lengthCounter = lengthCounter == 0 ? 64 : lengthCounter;
  }

  // Update the frequency timer based on the current frequency
  void updateFrequencyTimer() {
    frequencyTimer = (2048 - frequency) * 4;
  }

  // Update method called every CPU cycle
  void tick(int cycles) {
    if (!enabled) return;

    // Frequency timer
    frequencyTimer -= cycles;
    while (frequencyTimer <= 0) {
      frequencyTimer += (2048 - frequency) * 4;
      waveformIndex = (waveformIndex + 1) % 8;
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
    int dutyValue = dutyPatterns[dutyCycle][waveformIndex];
    int sample = dutyValue == 0 ? -volume : volume;
    return sample;
  }

  // Reset the channel
  void reset() {
    nr21 = 0;
    nr22 = 0;
    nr23 = 0;
    nr24 = 0;
    frequency = 0;
    frequencyTimer = 0;
    waveformIndex = 0;
    envelopeTimer = 0;
    lengthCounter = 0;
    volume = 0;
    enabled = false;
    dacEnabled = false;
    lengthEnabled = false;
    envelopeIncrease = false;
    envelopePeriod = 0;
  }

  // Frame sequencer reference (needs to be set from Audio class)
  int frameSequencer = 0;

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }
}
