import 'dart:io';
import 'dart:math';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';

class Audio {
  // Clock cycle accumulator for timing updates
  int clockCycleAccumulator = 0;
  int frameSequencer = 0;
  int divApu = 0;
  int mCycles = 0;

  int sampleRate = 44100; // Set your sample rate here
  List<int> audioBuffer = [];
  RandomAccessFile? audioFile; // The file to write audio samples to
  int totalSamplesWritten = 0;
  bool isWritingToFile = false;

  // Flag to indicate if recording is active
  bool recording = false;

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

  int mixAudioChannels() {
    // Combine audio outputs from all channels
    int mixedOutput = 0;
    mixedOutput += channel1.getOutput();
    mixedOutput += channel2.getOutput();
    mixedOutput += channel3.getOutput();
    mixedOutput += channel4.getOutput();

    // Debugging: Print the mixed output before clamping
    // print("Mixed Output: $mixedOutput");

    // Return the clamped value within the 16-bit range
    return mixedOutput.clamp(-32768, 32767);
  }

  void tick(int delta) {
    clockCycleAccumulator += delta;

    channel1.tick(delta);
    channel2.tick(delta);
    channel3.tick(delta);
    channel4.tick(delta);

    // Only process audio if recording is active
    if (recording && clockCycleAccumulator >= CPU.frequency ~/ sampleRate) {
      int mixedOutput = mixAudioChannels();
      mixedOutput = mixedOutput.clamp(-32768, 32767);

      // Add mixed output to the audio buffer (16-bit signed samples)
      audioBuffer.add(mixedOutput);

      clockCycleAccumulator -= CPU.frequency ~/ sampleRate;
    }
  }

  /// Starts recording audio
  Future<void> startRecording() async {
    // Clear the buffer and reset the total sample count
    audioBuffer.clear();
    totalSamplesWritten = 0;

    // Open the file to write audio data
    audioFile = await File("output.wav").open(mode: FileMode.write);

    // Write a placeholder WAV header (we'll overwrite this later with the correct size)
    await audioFile!.writeFrom(_generateWaveHeader(0));

    // Set recording to active
    recording = true;
  }

  /// Stops recording and writes the buffer to the file
  Future<void> stopRecording() async {
    if (audioFile != null) {
      // Set recording to inactive
      recording = false;

      // Flush remaining audio data to the file
      await _flushAudioBuffer();

      // Go back and update the WAV header with the correct size info
      await audioFile!.setPosition(0);
      await audioFile!.writeFrom(_generateWaveHeader(totalSamplesWritten));

      // Close the file
      await audioFile!.close();
      audioFile = null;
    }
  }

  /// Flush the audio buffer to the file
  Future<void> _flushAudioBuffer() async {
    if (audioBuffer.isEmpty || audioFile == null) return;

    // Convert the audio buffer to bytes
    List<int> byteBuffer = [];
    for (int sample in audioBuffer) {
      byteBuffer.add(sample & 0xFF); // Write low byte
      byteBuffer.add((sample >> 8) & 0xFF); // Write high byte
    }

    // Write the buffer to the file
    await audioFile!.writeFrom(byteBuffer);

    // Increment the total samples written
    totalSamplesWritten += audioBuffer.length;

    // Clear the buffer
    audioBuffer.clear();
  }

  /// Generate the WAV header based on the number of samples written
  List<int> _generateWaveHeader(int totalSamples) {
    int byteRate = sampleRate * 2; // 2 bytes per sample
    int dataSize = totalSamples * 2; // 16-bit (2 bytes per sample)

    return [
      // "RIFF" chunk descriptor
      0x52, 0x49, 0x46, 0x46, // Chunk ID ("RIFF")
      (36 + dataSize) & 0xFF,
      ((36 + dataSize) >> 8) & 0xFF,
      ((36 + dataSize) >> 16) & 0xFF,
      ((36 + dataSize) >> 24) & 0xFF, // Chunk size
      0x57, 0x41, 0x56, 0x45, // Format ("WAVE")

      // "fmt " sub-chunk
      0x66, 0x6D, 0x74, 0x20, // Sub-chunk ID ("fmt ")
      16, 0, 0, 0, // Sub-chunk size (16 for PCM)
      1, 0, // Audio format (1 for PCM)
      1, 0, // Number of channels (1 for mono)
      sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, (sampleRate >> 16) & 0xFF,
      (sampleRate >> 24) & 0xFF, // Sample rate
      byteRate & 0xFF, (byteRate >> 8) & 0xFF, (byteRate >> 16) & 0xFF,
      (byteRate >> 24) & 0xFF, // Byte rate
      2, 0, // Block align (2 bytes per sample)
      16, 0, // Bits per sample (16 bits)

      // "data" sub-chunk
      0x64, 0x61, 0x74, 0x61, // Sub-chunk ID ("data")
      dataSize & 0xFF, (dataSize >> 8) & 0xFF, (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF // Sub-chunk size
    ];
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

  int waveformPhase = 0; // Track the position in the waveform cycle
  int cycleLength =
      441; // For example, for a 441 Hz tone at 44.1 kHz sample rate

  int waveformHigh = 200; // Amplitude for the high phase of the square wave
  int waveformLow = -200; // Amplitude for the low phase of the square wave

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
    enabled = true;
    // Handle the sweep logic here
  }

  void writeNR11(int value) {
    nrx1 = value;
    enabled = true;
    // Handle sound length/wave duty update
  }

  void writeNR12(int value) {
    nrx2 = value;
    enabled = true;
    // Handle volume envelope update
  }

  void writeNR13(int value) {
    nrx3 = value;
    enabled = true;
    // Handle frequency low update
  }

  void writeNR14(int value) {
    nrx4 = value;
    enabled = true;
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

  void tick(int delta) {
    if (!enabled) return;

    // Update waveformPhase based on delta (CPU cycles passed)
    waveformPhase += delta;

    // Reset the phase when the end of the cycle is reached
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0; // Reset phase at the end of the waveform cycle
    }
  }

  int getOutput() {
    if (!enabled) return 0;

    // Generate square wave: if we are in the first half of the cycle, return high; otherwise, return low
    if (waveformPhase < cycleLength / 2) {
      return waveformHigh;
    } else {
      return waveformLow;
    }
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
    enabled = true;
    // Handle sound length/wave duty update
  }

  void writeNR22(int value) {
    nrx2 = value;
    enabled = true;
    // Handle volume envelope update
  }

  void writeNR23(int value) {
    nrx3 = value;
    enabled = true;
    // Handle frequency low update
  }

  void writeNR24(int value) {
    nrx4 = value;
    enabled = true;
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
