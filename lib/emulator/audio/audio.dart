import 'dart:math';
import 'package:dartboy/emulator/memory/memory_registers.dart';

class Audio {
  // Clock cycle accumulator for timing updates
  int clockCycleAccumulator = 0;
  int frameSequencer = 0;
  int divApu = 0;
  int mCycles = 0;

  // Variables for each channel and overall sound control
  Channel1 channel1 = Channel1();
  Channel2 channel2 = Channel2();
  Channel3 channel3 = Channel3();
  Channel4 channel4 = Channel4();
  int nr50 = 0;
  int nr51 = 0;
  int nr52 = 0;

  /// Reset the audio system (this is called during CPU reset)
  void reset() {
    clockCycleAccumulator = 0;
    frameSequencer = 0;
    channel1.reset();
    channel2.reset();
    channel3.reset();
    channel4.reset();
    nr50 = 0;
    nr51 = 0;
    nr52 = 0x80; // Set NR52 to the correct initial state (sound off, bit 7)
  }

  /// Tick the audio system.
  /// This method updates all audio channels and processes the audio output.
  void tick(int delta) {
    clockCycleAccumulator += delta;
    channel1.tick(delta);
    channel2.tick(delta);
    channel3.tick(delta);
    channel4.tick(delta);

    // Update the frame sequencer every 8192 cycles
    if (clockCycleAccumulator >= 8192) {
      frameSequencer = (frameSequencer + 1) % 8;

      if (frameSequencer == 0 ||
          frameSequencer == 2 ||
          frameSequencer == 4 ||
          frameSequencer == 6) {
        channel1.updateLengthCounter();
        channel2.updateLengthCounter();
        channel3.updateLengthCounter();
        channel4.updateLengthCounter();
      }
      if (frameSequencer == 7) {
        channel1.updateEnvelope();
        channel2.updateEnvelope();
        channel4.updateEnvelope();
      }
      if (frameSequencer == 2 || frameSequencer == 6) {
        channel1.updateSweep();
      }

      clockCycleAccumulator -= 8192;
    }
  }

  /// Read methods for the sound registers
  int readNR(int address) {
    switch (address) {
      case MemoryRegisters.nr10:
        return channel1.readNR10();
      case MemoryRegisters.nr11:
        return channel1.readNR11();
      case MemoryRegisters.nr12:
        return channel1.readNR12();
      case MemoryRegisters.nr13:
        return channel1.readNR13();
      case MemoryRegisters.nr14:
        return channel1.readNR14();

      case MemoryRegisters.nr21:
        return channel2.readNR21();
      case MemoryRegisters.nr22:
        return channel2.readNR22();
      case MemoryRegisters.nr23:
        return channel2.readNR23();
      case MemoryRegisters.nr24:
        return channel2.readNR24();

      case MemoryRegisters.nr30:
        return channel3.readNR30();
      case MemoryRegisters.nr31:
        return channel3.readNR31();
      case MemoryRegisters.nr32:
        return channel3.readNR32();
      case MemoryRegisters.nr33:
        return channel3.readNR33();
      case MemoryRegisters.nr34:
        return channel3.readNR34();

      case MemoryRegisters.nr41:
        return channel4.readNR41();
      case MemoryRegisters.nr42:
        return channel4.readNR42();
      case MemoryRegisters.nr43:
        return channel4.readNR43();
      case MemoryRegisters.nr44:
        return channel4.readNR44();
      case MemoryRegisters.nr50:
        return readNR50();
      case MemoryRegisters.nr51:
        return readNR51();
      case MemoryRegisters.nr52:
        return readNR52();
      default:
        return 0xFF; // Invalid read
    }
  }

  /// Write methods for the sound registers
  void writeNR(int address, int value) {
    switch (address) {
      case MemoryRegisters.nr10:
        channel1.writeNR10(value);
        break;
      case MemoryRegisters.nr11:
        channel1.writeNR11(value);
        break;
      case MemoryRegisters.nr12:
        channel1.writeNR12(value);
        break;
      case MemoryRegisters.nr13:
        channel1.writeNR13(value);
        break;
      case MemoryRegisters.nr14:
        channel1.writeNR14(value);
        break;

      case MemoryRegisters.nr21:
        channel2.writeNR21(value);
        break;
      case MemoryRegisters.nr22:
        channel2.writeNR22(value);
        break;
      case MemoryRegisters.nr23:
        channel2.writeNR23(value);
        break;
      case MemoryRegisters.nr24:
        channel2.writeNR24(value);
        break;

      case MemoryRegisters.nr30:
        channel3.writeNR30(value);
        break;
      case MemoryRegisters.nr31:
        channel3.writeNR31(value);
        break;
      case MemoryRegisters.nr32:
        channel3.writeNR32(value);
        break;
      case MemoryRegisters.nr33:
        channel3.writeNR33(value);
        break;
      case MemoryRegisters.nr34:
        channel3.writeNR34(value);
        break;

      case MemoryRegisters.nr41:
        channel4.writeNR41(value);
        break;
      case MemoryRegisters.nr42:
        channel4.writeNR42(value);
        break;
      case MemoryRegisters.nr43:
        channel4.writeNR43(value);
        break;
      case MemoryRegisters.nr44:
        channel4.writeNR44(value);
        break;
      case MemoryRegisters.nr50:
        writeNR50(value);
        break;
      case MemoryRegisters.nr51:
        writeNR51(value);
        break;
      case MemoryRegisters.nr52:
        writeNR52(value);
        break;
      default:
        // Invalid write
        break;
    }
  }

  /// NR50: Master volume control
  int readNR50() => nr50;
  void writeNR50(int value) => nr50 = value;

  /// NR51: Panning control (left/right output)
  int readNR51() => nr51;
  void writeNR51(int value) => nr51 = value;

  /// NR52: Sound on/off and channel status
  int readNR52() => nr52 | 0x70;
  void writeNR52(int value) {
    value &= 0xF0;
    if ((value & 0x80) == 0) {
      channel1.reset();
      channel2.reset();
      channel3.reset();
      channel4.reset();
      nr50 = 0;
      nr51 = 0;
    }
    nr52 = value;
  }
}

// Implement read and write methods for each channel
class Channel1 {
  int nrx0 = 0; // Sweep
  int nrx1 = 0; // Sound Length/Wave Duty
  int nrx2 = 0; // Volume Envelope
  int nrx3 = 0; // Frequency low
  int nrx4 = 0; // Frequency high + Control

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;

  int envelopeSweep = 0;
  int envelopeTimer = 0;
  bool envelopeDirection = false;
  int volume = 0;

  int sweepTime = 0;
  int sweepShift = 0;
  bool sweepDirection = false;
  bool sweepEnabled = false;
  int sweepTimer = 0;

  int frequency = 0;

  int readNR10() => nrx0 | 0x80;
  int readNR11() => nrx1 | 0x3F;
  int readNR12() => nrx2;
  int readNR13() => nrx3 | 0xFF;
  int readNR14() => nrx4 | 0xBF;

  void writeNR10(int value) {
    nrx0 = value;
    // Handle the sweep logic here
  }

  void writeNR11(int value) {
    nrx1 = value;
    // Handle sound length/wave duty update
  }

  void writeNR12(int value) {
    nrx2 = value;
    // Handle volume envelope update
  }

  void writeNR13(int value) {
    nrx3 = value;
    // Handle frequency low update
  }

  void writeNR14(int value) {
    nrx4 = value;
    // Handle frequency high and control update
  }

  void reset() {
    nrx0 = 0;
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
  }

  /// Tick method for Channel 1, updates the square wave generation.
  void tick(int delta) {
    // Update the frequency, volume, and other properties based on elapsed CPU cycles
    // Simulate the sound wave generation based on the channel's properties
    if (!enabled) {
      return;
    }

    // Here, update the frequency, volume, and other internal state based on the delta time
    // Implement the envelope, frequency sweep, etc.
  }

  // Length counter logic
  void updateLengthCounter() {
    // Only update length counter if the length is enabled
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Turn off the channel when length expires
      }
    }
  }

  // Envelope logic
  void updateEnvelope() {
    if (envelopeSweep > 0) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopeSweep; // Reset timer
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

  // Sweep logic (only for Channel 1)
  void updateSweep() {
    // Handle frequency sweep, similar to the C code
    if (sweepTime > 0 && sweepEnabled) {
      sweepTimer--;
      if (sweepTimer <= 0) {
        sweepTimer = sweepTime; // Reset sweep timer
        // Calculate new frequency and check for overflow
        int newFrequency = calculateSweepFrequency();
        if (newFrequency > 2047) {
          enabled = false; // Disable channel if overflowed
        } else if (sweepShift > 0) {
          frequency = newFrequency;
        }
      }
    }
  }

  // Method to calculate the new frequency during a sweep
  int calculateSweepFrequency() {
    int shift = frequency >> sweepShift;
    if (sweepDirection) {
      return frequency - shift; // Decrease frequency
    } else {
      return frequency + shift; // Increase frequency
    }
  }

  /// Return the current output for this channel
  int getOutput() {
    if (!enabled) {
      return 0;
    }
    // Generate and return the output based on the current frequency and volume
    // For a square wave, toggle between high and low values
    return (sin(nrx3) * nrx2).toInt(); // Simplified example
  }
}

class Channel2 {
  int nrx1 = 0; // Sound Length/Wave Duty
  int nrx2 = 0; // Volume Envelope
  int nrx3 = 0; // Frequency low
  int nrx4 = 0; // Frequency high + Control

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;

  int envelopeSweep = 0;
  int envelopeTimer = 0;
  bool envelopeDirection = false;
  int volume = 0;

  int frequency = 0;

  int readNR21() => nrx1 | 0x3F;
  int readNR22() => nrx2;
  int readNR23() => nrx3 | 0xFF;
  int readNR24() => nrx4 | 0xBF;

  void writeNR21(int value) {
    nrx1 = value;
    // Handle sound length/wave duty update
  }

  void writeNR22(int value) {
    nrx2 = value;
    // Handle volume envelope update
  }

  void writeNR23(int value) {
    nrx3 = value;
    // Handle frequency low update
  }

  void writeNR24(int value) {
    nrx4 = value;
    // Handle frequency high and control update
  }

  void reset() {
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
  }

  /// Tick method for Channel 2, updates the square wave generation.
  void tick(int delta) {
    if (!enabled) {
      return;
    }

    // Update frequency, volume, and other properties for the square wave
    // Implement the envelope and frequency logic
  }

  // Similar to Channel1 but without sweep logic
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }

  void updateEnvelope() {
    if (envelopeSweep > 0) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopeSweep;
        if (envelopeDirection) {
          if (volume < 15) {
            volume++;
          }
        } else {
          if (volume > 0) {
            volume--;
          }
        }
      }
    }
  }

  /// Return the current output for this channel.
  int getOutput() {
    if (!enabled) {
      return 0;
    }

    // Simplified square wave generation
    return (sin(nrx3) * nrx2).toInt();
  }
}

class Channel3 {
  int nrx0 = 0; // Sound ON/OFF
  int nrx1 = 0; // Sound Length
  int nrx2 = 0; // Output Level
  int nrx3 = 0; // Frequency low
  int nrx4 = 0; // Frequency high + Control

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;

  int readNR30() => nrx0 | 0x7F;
  int readNR31() => nrx1 | 0xFF;
  int readNR32() => nrx2 | 0x9F;
  int readNR33() => nrx3 | 0xFF;
  int readNR34() => nrx4 | 0xBF;

  void writeNR30(int value) {
    nrx0 = value;
    // Handle sound on/off
    enabled = (nrx0 & 0x80) != 0;
  }

  void writeNR31(int value) {
    nrx1 = value;
    // Handle sound length update
  }

  void writeNR32(int value) {
    nrx2 = value;
    // Handle output level update
  }

  void writeNR33(int value) {
    nrx3 = value;
    // Handle frequency low update
  }

  void writeNR34(int value) {
    nrx4 = value;
    // Handle frequency high and control update
  }

  void reset() {
    nrx0 = 0;
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
  }

  /// Tick method for Channel 3 (Wave channel)
  void tick(int delta) {
    if (!enabled) {
      return;
    }

    // Implement the frequency, wave table update logic
    // Update the sound based on elapsed CPU cycles
  }

  /// Return the current output for this channel.
  int getOutput() {
    if (!enabled) {
      return 0;
    }

    // Simplified wave channel output
    return (sin(nrx3) * nrx2).toInt();
  }

  // No envelope or sweep logic for Channel 3, only length
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }
}

class Channel4 {
  int nrx1 = 0; // Sound Length
  int nrx2 = 0; // Volume Envelope
  int nrx3 = 0; // Polynomial Counter
  int nrx4 = 0; // Counter/Consecutive; Initial

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;

  int envelopeSweep = 0;
  int envelopeTimer = 0;
  bool envelopeDirection = false;
  int volume = 0;

  int readNR41() => nrx1 | 0xFF;
  int readNR42() => nrx2;
  int readNR43() => nrx3;
  int readNR44() => nrx4 | 0xBF;

  void writeNR41(int value) {
    nrx1 = value;
    // Handle sound length update
  }

  void writeNR42(int value) {
    nrx2 = value;
    // Handle volume envelope update
  }

  void writeNR43(int value) {
    nrx3 = value;
    // Handle polynomial counter update
  }

  void writeNR44(int value) {
    nrx4 = value;
    // Handle counter/consecutive and initial settings
  }

  void reset() {
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
  }

  /// Tick method for Channel 4 (Noise channel)
  void tick(int delta) {
    if (!enabled) {
      return;
    }

    // Update noise generation logic based on polynomial counter and envelope
  }

  // Length counter logic
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false;
      }
    }
  }

  // Envelope logic for noise channel
  void updateEnvelope() {
    if (envelopeSweep > 0) {
      envelopeTimer--;
      if (envelopeTimer <= 0) {
        envelopeTimer = envelopeSweep;
        if (envelopeDirection) {
          if (volume < 15) {
            volume++;
          }
        } else {
          if (volume > 0) {
            volume--;
          }
        }
      }
    }
  }

  /// Return the current output for this channel.
  int getOutput() {
    if (!enabled) {
      return 0;
    }

    // Simplified noise channel output
    return (randomNoise(nrx3) * nrx2)
        .toInt(); // A simple random noise generator example
  }

  /// Simulate a noise generator (polynomial counter-based noise)
  int randomNoise(int polynomialCounter) {
    return Random().nextInt(2) * 2 - 1; // Simplified white noise generator
  }
}
