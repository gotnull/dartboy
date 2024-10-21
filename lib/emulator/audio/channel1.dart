class Channel1 {
  // Registers
  int nr10 = 0; // Sweep (NR10)
  int nr11 = 0; // Sound Length/Wave Duty (NR11)
  int nr12 = 0; // Volume Envelope (NR12)
  int nr13 = 0; // Frequency low (NR13)
  int nr14 = 0; // Frequency high + Control (NR14)

  // Internal variables
  int frequency = 0; // Current frequency (11 bits)
  int frequencyTimer = 0; // Frequency timer
  int waveformIndex = 0; // Current position in waveform (0-7)
  int sweepTimer = 0; // Timer for the frequency sweep
  int envelopeTimer = 0; // Timer for the volume envelope
  int lengthCounter = 0; // Length counter
  int volume = 0; // Current volume (0-15)

  // Sweep variables
  bool sweepEnabled = false;
  bool sweepNegate =
      false; // Sweep direction (false for increase, true for decrease)
  int sweepPeriod = 0;
  int sweepShift = 0;
  int shadowFrequency = 0;

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

  // DAC enabled flag (determined by NR12)
  bool dacEnabled = false;

  // Constructor
  Channel1();

  // NR10: Sweep Register
  int readNR10() => nr10 | 0x80; // Bit 7 is always read as 1
  void writeNR10(int value) {
    nr10 = value;
    sweepPeriod = (nr10 >> 4) & 0x07;
    sweepNegate = (nr10 & 0x08) != 0;
    sweepShift = nr10 & 0x07;
    sweepEnabled = sweepPeriod != 0 || sweepShift != 0;
  }

  // NR11: Sound Length / Waveform Duty
  int readNR11() => nr11 | 0x3F; // Bits 0-5 are unused/read-only
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
    dacEnabled = (nr12 & 0xF8) != 0;
    if (!dacEnabled) {
      enabled = false;
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
  int readNR14() => nr14 | 0xBF; // Bits 6-7 are unused/read-only
  void writeNR14(int value) {
    bool wasLengthEnabled = lengthEnabled;
    nr14 = value;
    lengthEnabled = (nr14 & 0x40) != 0;
    frequency = (nr14 & 0x07) << 8 | nr13;
    updateFrequencyTimer();
    if ((nr14 & 0x80) != 0) {
      trigger();
    }
    if (!wasLengthEnabled &&
        lengthEnabled &&
        lengthCounter == 0 &&
        frameSequencer == 0) {
      lengthCounter = 63;
    }
  }

  // Trigger the channel (on write to NR14 with bit 7 set)
  void trigger() {
    enabled = dacEnabled;
    frequencyTimer = (2048 - frequency) * 4;
    waveformIndex = 0;
    envelopeTimer = envelopePeriod == 0 ? 8 : envelopePeriod;
    volume = (nr12 >> 4) & 0x0F;
    lengthCounter = lengthCounter == 0 ? 64 : lengthCounter;
    shadowFrequency = frequency;
    sweepTimer = sweepPeriod == 0 ? 8 : sweepPeriod;
    sweepEnabled = sweepPeriod != 0 || sweepShift != 0;
    if (sweepShift != 0) {
      calculateSweepFrequency();
    }
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
        if (newFrequency <= 2047 && sweepShift != 0) {
          frequency = newFrequency;
          shadowFrequency = newFrequency;
          updateFrequencyTimer();
          calculateSweepFrequency(); // Second calculation for overflow check
        } else {
          enabled = false;
        }
      }
    }
  }

  // Calculate the new frequency for the sweep
  int calculateSweepFrequency() {
    int delta = shadowFrequency >> sweepShift;
    int newFrequency =
        sweepNegate ? shadowFrequency - delta : shadowFrequency + delta;
    if (newFrequency > 2047) {
      enabled = false;
    }
    return newFrequency & 0x7FF; // Ensure 11-bit frequency
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
    nr10 = 0;
    nr11 = 0;
    nr12 = 0;
    nr13 = 0;
    nr14 = 0;
    frequency = 0;
    frequencyTimer = 0;
    waveformIndex = 0;
    sweepTimer = 0;
    envelopeTimer = 0;
    lengthCounter = 0;
    volume = 0;
    enabled = false;
    dacEnabled = false;
    sweepEnabled = false;
    lengthEnabled = false;
    envelopeIncrease = false;
    sweepNegate = false;
    sweepPeriod = 0;
    sweepShift = 0;
    shadowFrequency = 0;
    envelopePeriod = 0;
  }

  // Frame sequencer reference (needs to be set from Audio class)
  int frameSequencer = 0;

  // Set frame sequencer value (called from Audio class)
  void setFrameSequencer(int value) {
    frameSequencer = value;
  }
}
