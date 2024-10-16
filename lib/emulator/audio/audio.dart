import 'dart:async';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:ffi/ffi.dart';

// Load the dynamic library
final DynamicLibrary audioLib = DynamicLibrary.open('libaudio.dylib');

// FFI function bindings
typedef InitAudioNative = Int32 Function(
    Int32 sampleRate, Int32 channels, Int32 bufferSize);
typedef InitAudioDart = int Function(
    int sampleRate, int channels, int bufferSize);

typedef StreamAudioNative = Void Function(Pointer<Uint8> buffer, Int32 length);
typedef StreamAudioDart = void Function(Pointer<Uint8> buffer, int length);

typedef TerminateAudioNative = Void Function();
typedef TerminateAudioDart = void Function();

// Dart bindings for C functions in the library
final InitAudioDart initAudio =
    audioLib.lookup<NativeFunction<InitAudioNative>>('init_audio').asFunction();

final StreamAudioDart streamAudio = audioLib
    .lookup<NativeFunction<StreamAudioNative>>('stream_audio')
    .asFunction();

final TerminateAudioDart terminateAudio = audioLib
    .lookup<NativeFunction<TerminateAudioNative>>('terminate_audio')
    .asFunction();

class Audio {
  // Clock cycle accumulator for timing updates
  int clockCycleAccumulator = 0;
  int frameSequencer = 0;

  int sampleRate = 44100; // Set your sample rate here
  int bufferSize = 2048;
  int previousSample = 0;

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

  // Audio initialization state
  bool isInitialized = false;
  int channels = 2; // Stereo sound

  // Init function to set up the player
  Future<void> init() async {
    // Initialize SDL2 audio with the defined sample rate and buffer size
    int result = initAudio(sampleRate, channels, bufferSize);
    if (result != 0) {
      print('Failed to initialize audio.');
      return;
    }
    isInitialized = true;
  }

  void tick(int delta) {
    if (!isInitialized) return;

    clockCycleAccumulator += delta;

    // Process sound channels
    channel1.tick(delta);
    channel2.tick(delta);
    channel3.tick(delta);
    channel4.tick(delta);

    // Generate an audio sample at the correct rate
    if (clockCycleAccumulator >= CPU.frequency ~/ sampleRate) {
      int mixedOutput = mixAudioChannels();
      //mixedOutput = applyLowPassFilter(mixedOutput);

      Uint8List audioData = convertToPCM(mixedOutput);

      // Stream the audio data to SDL2
      final Pointer<Uint8> bufferPtr = malloc.allocate<Uint8>(audioData.length);
      bufferPtr.asTypedList(audioData.length).setAll(0, audioData);
      streamAudio(bufferPtr, audioData.length);
      malloc.free(bufferPtr);

      // Reset clock accumulator for the next sample
      clockCycleAccumulator -= CPU.frequency ~/ sampleRate;
    }
  }

  int applyLowPassFilter(int currentSample) {
    int filteredSample = (previousSample + currentSample) ~/ 2;
    previousSample = currentSample;
    return filteredSample;
  }

  /// Converts mixed audio output to PCM format
  Uint8List convertToPCM(int mixedOutput) {
    // Scale the mixed output from Gameboy's 4-bit range to 16-bit signed range
    int scaledOutput =
        (mixedOutput * 32767) ~/ 15; // Scale from 0-15 to -32768 to 32767

    // Convert to 16-bit signed PCM format (little-endian)
    return Uint8List(2)
      ..[0] = scaledOutput & 0xFF // Low byte
      ..[1] = (scaledOutput >> 8) & 0xFF; // High byte
  }

  // Stop the audio system
  Future<void> stopAudio() async {
    if (isInitialized) {
      terminateAudio();
      isInitialized = false;
    }
  }

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

  void tickFrameSequencer(int cycles) {
    // Advance the frame sequencer with every 512 cycles (CPU clocked at 4194304 Hz)
    frameSequencer += cycles;

    if (frameSequencer >= CPU.frequency ~/ 512) {
      frameSequencer -= CPU.frequency ~/ 512;
      // Step through the sequencer:
      switch (frameSequencer % 8) {
        case 0:
          channel1.updateLengthCounter();
          channel2.updateLengthCounter();
          channel3.updateLengthCounter();
          channel4.updateLengthCounter();
          break;
        case 2:
          channel1.updateSweep();
          break;
        case 4:
          channel1.updateLengthCounter();
          channel2.updateLengthCounter();
          channel3.updateLengthCounter();
          channel4.updateLengthCounter();
          break;
        case 7:
          channel1.updateEnvelope();
          channel2.updateEnvelope();
          channel4.updateEnvelope();
          break;
      }
    }
  }

  int mixAudioChannels() {
    int left = 0;
    int right = 0;

    if (nr51 & 0x01 != 0) left += channel1.getOutput();
    if (nr51 & 0x10 != 0) right += channel1.getOutput();

    if (nr51 & 0x02 != 0) left += channel2.getOutput();
    if (nr51 & 0x20 != 0) right += channel2.getOutput();

    if (nr51 & 0x04 != 0) left += channel3.getOutput();
    if (nr51 & 0x40 != 0) right += channel3.getOutput();

    if (nr51 & 0x08 != 0) left += channel4.getOutput();
    if (nr51 & 0x80 != 0) right += channel4.getOutput();

    // Apply master volume control from NR50
    left = (left * ((nr50 >> 4) & 0x07)) ~/ 7;
    right = (right * (nr50 & 0x07)) ~/ 7;

    // Check if all channels are silent
    if (left == 0 && right == 0) {
      return 0; // Output silence when no audio is playing
    }

    // Return the mixed output, clamped to 16-bit PCM range
    return (left + right).clamp(-32768, 32767);
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

    // Enable the channel if envelope parameters are valid
    if (volume > 0 || envelopeSweep > 0) {
      enabled = true;
    }
  }

  void writeNR13(int value) {
    nrx3 = value;
    frequency = (nrx4 & 0x7) << 8 |
        nrx3; // Combine the two registers to get the full frequency
    cycleLength = (2048 - frequency) * 4; // Update cycle length
  }

  void writeNR14(int value) {
    nrx4 = value;
    frequency = (nrx4 & 0x7) << 8 | nrx3;
    cycleLength = (2048 - frequency) * 4;

    if ((value & 0x80) != 0) {
      // If bit 7 is set, trigger the channel
      waveformPhase = 0;
      enabled = true;

      // Reload envelope timer and volume
      envelopeTimer = envelopeSweep;
      volume = (nrx2 >> 4) & 0xF;

      // Perform immediate frequency sweep if enabled
      if (sweepShift > 0 || sweepDirection) {
        updateSweep();
      }

      // Reload frequency timer
      cycleLength = (2048 - frequency) * 4;
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

  // Generate square wave based on duty cycle
  int getOutput() {
    if (!enabled) return 0;

    // Use the duty cycle to determine the high/low phases of the square wave
    int dutyCycle = (nrx1 >> 6) & 0x3; // Get the duty cycle from NRx1

    // Define duty patterns using hexadecimal equivalents of binary values
    int dutyPattern = [
      0x01, // 00000001 (12.5%)
      0x81, // 10000001 (25%)
      0xC7, // 11000111 (50%)
      0x7E // 01111110 (75%)
    ][dutyCycle];

    // Determine if the current phase is high or low based on the duty cycle
    if ((dutyPattern & (1 << (waveformPhase >> (cycleLength ~/ 8)))) != 0) {
      return waveformHigh; // High phase
    } else {
      return waveformLow; // Low phase
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
    updateCycleLength();

    // Enable the channel when sound length is configured
    enabled = true;
  }

  void writeNR23(int value) {
    nrx3 = value;
    updateFrequency();
    updateCycleLength();
  }

  void writeNR24(int value) {
    nrx4 = value;
    frequency = (nrx4 & 0x7) << 8 | nrx3;
    cycleLength = (2048 - frequency) * 4;

    if ((value & 0x80) != 0) {
      // Trigger the channel
      waveformPhase = 0;
      enabled = true;

      // Reload envelope timer and volume
      envelopeTimer = envelopeSweep;
      volume = (nrx2 >> 4) & 0xF;

      // Reload frequency timer
      cycleLength = (2048 - frequency) * 4;
    }
  }

  void writeNR22(int value) {
    nrx2 = value;

    // Enable the channel when envelope parameters are set
    if (volume > 0 || envelopeSweep > 0) {
      enabled = true;
    }
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
  int nrx0 = 0; // Sound ON/OFF (NR30)
  int nrx1 = 0; // Sound Length (NR31)
  int nrx2 = 0; // Output Level (NR32)
  int nrx3 = 0; // Frequency low (NR33)
  int nrx4 = 0; // Frequency high + Control (NR34)

  bool enabled = false;
  bool lengthEnabled = false;
  int lengthCounter = 0;
  int frequency = 0;
  int outputLevel = 0; // Volume control

  // Waveform data (32 samples, 4-bit each)
  List<int> waveformData = List.filled(32, 0);

  int sampleBuffer = 0; // Buffer to store the current sample
  int currentSampleIndex = 0; // Index of the current sample in the waveform
  int waveformPhase = 0; // Tracks the current phase within the waveform cycle

  int cycleLength = 0; // Frequency timer period

  int readNR30() => nrx0 | 0x7F;
  int readNR31() => nrx1 | 0xFF;
  int readNR32() => nrx2 | 0x9F;
  int readNR33() => nrx3 | 0xFF;
  int readNR34() => nrx4 | 0xBF;

  /// NR30: Sound ON/OFF
  void writeNR30(int value) {
    nrx0 = value;
    enabled = (nrx0 & 0x80) != 0; // If bit 7 is set, channel is enabled

    if (!enabled) {
      reset(); // Reset the channel if it's disabled
    }
  }

  /// NR31: Sound Length (256 steps)
  void writeNR31(int value) {
    nrx1 = value;
    lengthCounter = 256 - value; // Set the length counter based on NR31
  }

  /// NR32: Output Level (Volume Control)
  void writeNR32(int value) {
    nrx2 = value;
    // Output level (00 = mute, 01 = full volume, 10 = half, 11 = quarter)
    outputLevel = (nrx2 >> 5) & 0x03;
  }

  /// NR33: Frequency Low (lower 8 bits of frequency)
  void writeNR33(int value) {
    nrx3 = value;
    frequency = (nrx4 & 0x07) << 8 | nrx3; // Combine NR33 and NR34
    cycleLength = (2048 - frequency) * 2; // Set cycle length based on frequency
  }

  /// NR34: Frequency High and Control
  void writeNR34(int value) {
    nrx4 = value;
    frequency = (nrx4 & 0x07) << 8 | nrx3;
    cycleLength = (2048 - frequency) * 2;

    if ((nrx4 & 0x80) != 0) {
      restartWaveform(); // Restart waveform when triggered
      enabled = true;
    }

    // Enable length counter if bit 6 is set
    lengthEnabled = (nrx4 & 0x40) != 0;
  }

  /// Restart the waveform playback (trigger event)
  void restartWaveform() {
    waveformPhase = 0; // Reset waveform phase
    currentSampleIndex = 0; // Reset to the beginning of the wave table
    sampleBuffer = waveformData[currentSampleIndex]; // Load the first sample
  }

  /// Length counter logic
  void updateLengthCounter() {
    if (lengthEnabled && lengthCounter > 0) {
      lengthCounter--;
      if (lengthCounter == 0) {
        enabled = false; // Disable the channel when length counter reaches 0
      }
    }
  }

  /// Tick method for Channel 3 (Wave channel)
  void tick(int delta) {
    if (!enabled) return;

    // Update the waveform phase based on elapsed cycles
    waveformPhase += delta;

    // Each sample is played over a cycle, and the phase advances through the waveform
    if (waveformPhase >= cycleLength) {
      waveformPhase = 0; // Reset the phase
      currentSampleIndex =
          (currentSampleIndex + 1) % 32; // Move to the next sample
      sampleBuffer = waveformData[currentSampleIndex]; // Load the next sample
    }
  }

  /// Get the current output from Channel 3
  int getOutput() {
    if (!enabled || outputLevel == 0) {
      return 0; // Return 0 if the channel is disabled or muted
    }

    // Scale output based on the NR32 (volume control)
    int scaledOutput = (sampleBuffer >> (4 - outputLevel)) &
        0xF; // Adjust output based on volume

    // Return the scaled output value
    return (scaledOutput * 2) - 15; // Normalize to signed value (-15 to 15)
  }

  /// Resets the state of Channel 3
  void reset() {
    nrx0 = 0;
    nrx1 = 0;
    nrx2 = 0;
    nrx3 = 0;
    nrx4 = 0;
    enabled = false;
    lengthCounter = 0;
    waveformPhase = 0;
    currentSampleIndex = 0;
    sampleBuffer = 0;
    outputLevel = 0;
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
    lengthCounter = 64 - (value & 0x3F); // Set the length of noise playback

    // Enable the channel when sound length is configured
    enabled = true;
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

    if ((value & 0x80) != 0) {
      // Trigger the noise channel
      lengthCounter = 64;
      envelopeTimer = envelopeSweep;
      enabled = true;

      // Reset the LFSR (set all bits to 1)
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

  int getOutput() {
    if (!enabled) {
      return 0;
    }

    // Generate the noise and scale it by the current volume
    int noiseOutput = generateNoise();
    return noiseOutput * volume;
  }

  int generateNoise() {
    int feedback = (lfsr ^ (lfsr >> 1)) & 1;
    lfsr = (lfsr >> 1) | (feedback << 14);
    return feedback * 2 - 1; // Convert 0/1 to -1/1 for noise output
  }

  /// Simulate a noise generator (polynomial counter-based noise)
  int randomNoise(int polynomialCounter) {
    return Random().nextInt(2) * 2 - 1; // Simplified white noise generator
  }
}
