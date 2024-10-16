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

    // Extract sweep parameters
    int sweepTime = (value >> 4) & 0x7; // Sweep time in number of steps
    bool sweepDirection =
        (value & 0x08) == 0x08; // 1 for decrease, 0 for increase
    int sweepShift = value & 0x07; // Frequency shift

    if (sweepTime == 0) {
      sweepTime = 8; // According to hardware behavior
    }

    sweepTimer = sweepTime;
    sweepEnabled = sweepShift > 0 || sweepDirection;
  }

  void writeNR11(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // 64-step length counter for Channel 1
  }

  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Disable channel when the counter reaches zero
      }
    }
  }

  void writeNR12(int value) {
    nrx2 = value;

    volume = value & 0xF; // Initial volume
    envelopeDirection = (value & 0x08) != 0; // Increase if 1, decrease if 0
    envelopeSweep = (value >> 4) & 0x7; // Number of steps for envelope

    if (envelopeSweep == 0) {
      envelopeSweep = 8; // Default to 8 steps when set to 0
    }

    envelopeTimer = envelopeSweep;
  }

  void writeNR13(int value) {
    nrx3 = value;
    frequency = (nrx4 & 0x7) << 8 |
        nrx3; // Combine the two registers to get the full frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length
  }

  void writeNR14(int value) {
    nrx4 = value;
    frequency = (nrx4 & 0x7) << 8 |
        nrx3; // Combine the two registers to get the full frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length

    if ((value & 0x80) != 0) {
      // If bit 7 is set, reset waveform phase
      waveformPhase = 0;
      enabled = true; // Channel is enabled here
    }
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

  void updateSweep() {
    if (sweepEnabled && sweepTimer > 0) {
      sweepTimer--;
      if (sweepTimer == 0) {
        sweepTimer = sweepTime;
        int newFrequency = calculateSweepFrequency();
        if (newFrequency > 2047) {
          enabled = false; // Disable if frequency exceeds 2047
        } else {
          frequency = newFrequency;
          cycleLength = (2048 - frequency) * 4; // Update cycle length
        }
      }
    }
  }

  int calculateSweepFrequency() {
    int shiftedFrequency = frequency >> sweepShift;

    // Adjust frequency based on direction
    if (sweepDirection) {
      return frequency - shiftedFrequency; // Decrease frequency
    } else {
      return frequency + shiftedFrequency; // Increase frequency
    }
  }

  // Envelope logic
  void updateEnvelope() {
    if (envelopeSweep > 0) {
      envelopeTimer--;
      if (envelopeTimer == 0) {
        envelopeTimer = envelopeSweep; // Reset timer
        if (envelopeDirection && volume < 15) {
          volume++; // Increase volume
        } else if (!envelopeDirection && volume > 0) {
          volume--; // Decrease volume
        }
      }
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

  int waveformPhase = 0; // Tracks the current phase within the waveform cycle
  int cycleLength =
      2048; // The default cycle length (can be adjusted based on frequency)

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
    updateCycleLength();
  }

  void writeNR23(int value) {
    nrx3 = value;
    updateFrequency();
    updateCycleLength();
  }

  void writeNR24(int value) {
    nrx4 = value;
    frequency = (nrx4 & 0x7) << 8 | nrx3; // Update frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length

    if ((value & 0x80) != 0) {
      // If bit 7 is set, reset waveform phase and enable the channel
      waveformPhase = 0;
      enabled = true; // Channel is enabled here
    }
  }

  void writeNR22(int value) {
    nrx2 = value;
    enabled = true;
    // Handle volume envelope update
  }

  void reset() {
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
    waveformPhase = 0;
    cycleLength = 2048;
  }

  /// Updates the cycle length based on the current frequency.
  void updateCycleLength() {
    // Calculate the frequency from NR23 (low) and NR24 (high) registers
    int frequencyValue = (nrx4 & 0x07) << 8 | nrx3;

    // Convert the frequency into a cycle length. Higher frequencies = shorter cycles.
    if (frequencyValue > 0) {
      cycleLength = (2048 - frequencyValue) * 4;
    }
  }

  /// Updates the internal frequency based on NR23 and NR24.
  void updateFrequency() {
    frequency = (nrx4 & 0x07) << 8 | nrx3;
  }

  void updateEnvelope() {
    if (envelopeSweep > 0) {
      envelopeTimer--;
      if (envelopeTimer == 0) {
        envelopeTimer = envelopeSweep; // Reset timer
        if (envelopeDirection && volume < 15) {
          volume++; // Increase volume
        } else if (!envelopeDirection && volume > 0) {
          volume--; // Decrease volume
        }
      }
    }
  }

  /// Length counter logic (disables the channel when the length expires).
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Disable the channel when the length expires
      }
    }
  }

  /// Return the current output for this channel.
  int getOutput() {
    if (!enabled) return 0;

    // Generate square wave: if we are in the first half of the cycle, return high; otherwise, return low
    if (waveformPhase < cycleLength / 2) {
      return volume * 2; // High phase of the square wave
    } else {
      return -volume * 2; // Low phase of the square wave
    }
  }

  void tick(int delta) {
    if (!enabled) {
      return;
    }

    // Update waveform phase based on delta (CPU cycles passed)
    waveformPhase += delta;

    // Reset the phase when the end of the cycle is reached
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0; // Reset phase at the end of the waveform cycle
    }

    // Handle the envelope update (adjust volume over time)
    updateEnvelope();

    // Handle length counter (used to disable the channel after a certain period)
    updateLengthCounter();
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

  int waveformPhase = 0; // Tracks the current phase within the waveform cycle
  int outputLevel = 0; // Current output level (volume)
  int frequency = 0; // Current frequency

  int readNR30() => nrx0 | 0x7F;
  int readNR31() => nrx1 | 0xFF;
  int readNR32() => nrx2 | 0x9F;
  int readNR33() => nrx3 | 0xFF;
  int readNR34() => nrx4 | 0xBF;

  /// NR30: Sound ON/OFF
  void writeNR30(int value) {
    nrx0 = value;

    // If bit 7 is set, the channel is enabled (sound ON), otherwise, it's OFF
    enabled = (nrx0 & 0x80) != 0;

    // If the channel is disabled, reset its state
    if (!enabled) {
      reset();
    }
  }

  /// NR31: Sound Length
  void writeNR31(int value) {
    nrx1 = value;

    // The length is set based on the lower 8 bits of nrx1 (total length = 256 steps)
    lengthCounter = 256 - value; // Length of the waveform playback in steps
  }

  /// NR32: Output Level (Volume Control)
  void writeNR32(int value) {
    nrx2 = value;

    // Output level (volume control) is determined by bits 5 and 6 of nrx2
    // 00 = Mute (no sound), 01 = 100% volume, 10 = 50% volume, 11 = 25% volume
    switch ((nrx2 >> 5) & 0x03) {
      case 0:
        outputLevel = 0; // Mute
        break;
      case 1:
        outputLevel = 100; // Full volume
        break;
      case 2:
        outputLevel = 50; // Half volume
        break;
      case 3:
        outputLevel = 25; // Quarter volume
        break;
    }
  }

  /// NR33: Frequency Low (lower 8 bits of frequency)
  void writeNR33(int value) {
    nrx3 = value;

    // Combine NR33 (lower 8 bits) and NR34 (upper 3 bits) to update the full frequency
    frequency = (nrx4 & 0x07) << 8 | nrx3;
  }

  /// NR34: Frequency High and Control
  void writeNR34(int value) {
    nrx4 = value;

    // Combine NR33 (lower 8 bits) and NR34 (upper 3 bits) to update the full frequency
    frequency = (nrx4 & 0x07) << 8 | nrx3;

    // If bit 7 is set, trigger the sound (restart the waveform playback)
    if ((nrx4 & 0x80) != 0) {
      restartWaveform();
      enabled = true;
    }

    // If bit 6 is set, enable the length counter
    lengthEnabled = (nrx4 & 0x40) != 0;
  }

  /// Helper method to restart the waveform playback
  void restartWaveform() {
    // Reset the phase of the waveform
    waveformPhase = 0;

    // Enable the channel
    enabled = true;
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
  int lfsr = 0x7FFF; // 15-bit LFSR starting state
  int polynomialCounter = 0; // Polynomial counter (NR43)

  int envelopeSweep = 0;
  int envelopeTimer = 0;
  bool envelopeDirection = false;
  int volume = 0;

  int readNR41() => nrx1 | 0xFF;
  int readNR42() => nrx2;
  int readNR43() => nrx3;
  int readNR44() => nrx4 | 0xBF;

  /// NR41: Sound length (64 steps)
  void writeNR41(int value) {
    nrx1 = value;
    lengthCounter = 64 - (value & 0x3F); // Update length counter (6-bit value)
  }

  /// NR42: Volume envelope
  void writeNR42(int value) {
    nrx2 = value;
    volume = (value >> 4) & 0xF; // Initial volume (4 bits)
    envelopeDirection =
        (value & 0x08) != 0; // Envelope direction (1: increase, 0: decrease)
    envelopeSweep = value & 0x07; // Envelope sweep time (3 bits)

    if (envelopeSweep == 0) {
      envelopeSweep = 8; // When set to 0, behaves as 8 steps
    }

    envelopeTimer = envelopeSweep; // Reset envelope timer
  }

  /// NR43: Polynomial counter
  void writeNR43(int value) {
    nrx3 = value;

    // Extract and set polynomial counter divisor (controls frequency)
    int divisorCode = value & 0x7; // Lower 3 bits control the divisor
    int shiftClockFreq =
        (value >> 4) & 0xF; // Upper 4 bits for shift clock frequency

    // Determine the divisor value based on the divisor code
    int divisor = divisorCode == 0 ? 8 : divisorCode * 16;

    // Polynomial counter divisor behavior is frequency related
    // The noise frequency is affected by both the divisor and shiftClockFreq
    polynomialCounter = divisor << shiftClockFreq;

    // LFSR width control: 0 for 15-bit LFSR, 1 for 7-bit LFSR
    bool lfsrWidth = (value & 0x08) != 0;

    // Set LFSR mode: 15-bit or 7-bit
    if (lfsrWidth) {
      // 7-bit LFSR mode (only the lower 7 bits of the LFSR are used)
      lfsr &= 0x7F; // Clear upper bits and use only the lower 7 bits
    } else {
      // 15-bit LFSR mode (use the full 15 bits of the LFSR)
      lfsr &= 0x7FFF; // Use the full 15-bit value for LFSR
    }

    // Noise frequency updates will depend on the divisor and shiftClockFreq
    // Higher shiftClockFreq results in faster noise generation.
    // The polynomial counter and LFSR state will drive the noise waveform.
  }

  /// NR44: Counter/consecutive and initial
  void writeNR44(int value) {
    nrx4 = value;

    // If bit 7 is set, reset length counter and envelope
    if ((value & 0x80) != 0) {
      lengthCounter = 64; // Reset length counter
      envelopeTimer = envelopeSweep; // Reset envelope
      enabled = true; // Enable the channel here
    }

    // Length counter enable (bit 6)
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

  /// Tick method for Channel 4 (Noise channel)
  void tick(int delta) {
    if (!enabled) {
      return;
    }

    // Update length counter to disable the channel if the length expires
    updateLengthCounter();

    // Update envelope (adjusts volume over time)
    updateEnvelope();

    // Update noise generation based on the polynomial counter logic
    // This is influenced by the divisor and shift clock frequency
    polynomialCounter -= delta;

    // When the polynomial counter reaches zero, it's time to generate the next noise sample
    if (polynomialCounter <= 0) {
      // Reset the polynomial counter based on the divisor and shift clock frequency
      int shiftClockFreq = (nrx3 >> 4) & 0xF;
      int divisorCode = nrx3 & 0x7;

      // The actual frequency is calculated as (2^shiftClockFreq) * divisor
      int divisor = divisorCode == 0 ? 8 : divisorCode * 16;
      polynomialCounter = divisor << shiftClockFreq;

      // Generate the next noise sample using the LFSR
      generateNoise();
    }
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

  int generateNoise() {
    int feedback = (lfsr ^ (lfsr >> 1)) & 1;
    lfsr = (lfsr >> 1) | (feedback << 14);
    return feedback * 2 - 1; // Convert 0/1 to -1/1 for noise output
  }

  /// Return the current output for this channel.
  int getOutput() {
    if (!enabled) {
      return 0;
    }

    // Call the noise generator based on the LFSR
    int noiseOutput = generateNoise();

    // Scale the noise output by the current volume envelope
    return noiseOutput * volume;
  }

  /// Simulate a noise generator (polynomial counter-based noise)
  int randomNoise(int polynomialCounter) {
    return Random().nextInt(2) * 2 - 1; // Simplified white noise generator
  }
}
