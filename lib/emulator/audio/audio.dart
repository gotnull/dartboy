import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:dartboy/emulator/audio/channel1.dart';
import 'package:dartboy/emulator/audio/channel2.dart';
import 'package:dartboy/emulator/audio/channel3.dart';
import 'package:dartboy/emulator/audio/channel4.dart';
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
