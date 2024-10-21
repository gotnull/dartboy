import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartboy/emulator/audio/channel1.dart';
import 'package:dartboy/emulator/audio/channel2.dart';
import 'package:dartboy/emulator/audio/channel3.dart';
import 'package:dartboy/emulator/audio/channel4.dart';
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:ffi/ffi.dart';

// Load the shared library
final DynamicLibrary audioLib = DynamicLibrary.open('libaudio.dylib');

// FFI definitions for the functions in the shared library
typedef InitAudioNative = Int32 Function(
    Int32 sampleRate, Int32 channels, Int32 bufferSize);
typedef InitAudioDart = int Function(
    int sampleRate, int channels, int bufferSize);

typedef StreamAudioNative = Void Function(Pointer<Uint8> buffer, Int32 length);
typedef StreamAudioDart = void Function(Pointer<Uint8> buffer, int length);

typedef TerminateAudioNative = Void Function();
typedef TerminateAudioDart = void Function();

final InitAudioDart initAudio =
    audioLib.lookup<NativeFunction<InitAudioNative>>('init_audio').asFunction();

final StreamAudioDart streamAudio = audioLib
    .lookup<NativeFunction<StreamAudioNative>>('stream_audio')
    .asFunction();

final TerminateAudioDart terminateAudio = audioLib
    .lookup<NativeFunction<TerminateAudioNative>>('terminate_audio')
    .asFunction();

class Audio {
  static const int cpuClockSpeed = 4194304; // Game Boy CPU clock speed in Hz
  static const int frameSequencerRate = 512; // Hz
  static const int defaultSampleRate = 44100;
  static const int defaultBufferSize = 1024;
  static const int defaultChannels = 2;

  final int sampleRate = 44100;
  final int bufferSize = 1024;
  final int channels = 2;

  int cyclesPerSample;
  int cyclesPerFrameSequencer = 8192; // 4194304 / 512
  int accumulatedCycles = 0;
  int frameSequencerCycles = 0;
  int frameSequencer = 0;

  int leftVolume = 0; // Left master volume (0-7)
  int rightVolume = 0; // Right master volume (0-7)

  bool isInitialized = false;

  final Channel1 channel1 = Channel1();
  final Channel2 channel2 = Channel2();
  final Channel3 channel3 = Channel3();
  final Channel4 channel4 = Channel4();

  int nr50 = 0;
  int nr51 = 0;
  int nr52 = 0x80; // Sound on by default

  Audio(clockSpeed) : cyclesPerSample = clockSpeed ~/ defaultSampleRate;

  Future<void> init() async {
    int result = initAudio(sampleRate, channels, bufferSize);
    if (result != 0) {
      // Handle initialization error if necessary
    }
    isInitialized = Configuration.enableAudio;
  }

  // Update left and right channel volumes based on NR50 register
  void updateVolumes() {
    leftVolume = (nr50 >> 4) & 0x07; // Left volume is controlled by bits 4-6
    rightVolume = nr50 & 0x07; // Right volume is controlled by bits 0-2
  }

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
        return nr50;
      case MemoryRegisters.nr51:
        return nr51;
      case MemoryRegisters.nr52:
        return nr52 | 0x70; // Bits 4-6 are always read as 1 on NR52
      default:
        print("Unknown audio register read: ${address.toRadixString(16)}");
        return 0xFF; // Return 0xFF for unmapped addresses
    }
  }

  void writeNR(int address, int value) {
    if (address < MemoryRegisters.nr10 || address > MemoryRegisters.nr52) {
      print(
          "Unknown audio register write: ${address.toRadixString(16)} = $value");
      return;
    }

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
        nr50 = value;
        updateVolumes();
        break;
      case MemoryRegisters.nr51:
        nr51 = value;
        break;
      case MemoryRegisters.nr52:
        nr52 = (value & 0x80) | (nr52 & 0x7F);
        if ((value & 0x80) == 0) {
          // If master sound is disabled, reset all channels
          channel1.reset();
          channel2.reset();
          channel3.reset();
          channel4.reset();
          nr50 = 0;
          nr51 = 0;
          updateVolumes();
        }
        break;
    }
  }

  void updateClockSpeed(int newClockSpeed) {
    cyclesPerSample = newClockSpeed ~/ sampleRate;
    // cyclesPerFrameSequencer remains at 8192, as per Game Boy hardware
  }

  void tick(int cycles) {
    if (!isInitialized) return;

    accumulatedCycles += cycles;
    frameSequencerCycles += cycles;

    // Update frame sequencer every 8192 CPU cycles
    while (frameSequencerCycles >= cyclesPerFrameSequencer) {
      updateFrameSequencer();
      frameSequencerCycles -= cyclesPerFrameSequencer;
    }

    // Generate audio samples at the correct intervals
    while (accumulatedCycles >= cyclesPerSample) {
      mixAndQueueAudioSample();
      accumulatedCycles -= cyclesPerSample;
    }

    // Update each channel
    channel1.tick(cycles);
    channel2.tick(cycles);
    channel3.tick(cycles);
    channel4.tick(cycles);
  }

  void updateFrameSequencer() {
    // Update frame sequencer step
    frameSequencer = (frameSequencer + 1) % 8;

    // Set the frame sequencer value in Channel1
    channel1.setFrameSequencer(frameSequencer);
    channel2.setFrameSequencer(frameSequencer);
    channel3.setFrameSequencer(frameSequencer);
    channel4.setFrameSequencer(frameSequencer);

    switch (frameSequencer) {
      case 0:
        // Step 0: Length counters
        updateLengthCounters();
        break;
      case 1:
        // Step 1: Nothing
        break;
      case 2:
        // Step 2: Length counters, sweep
        updateLengthCounters();
        channel1.updateSweep();
        break;
      case 3:
        // Step 3: Nothing
        break;
      case 4:
        // Step 4: Length counters
        updateLengthCounters();
        break;
      case 5:
        // Step 5: Nothing
        break;
      case 6:
        // Step 6: Length counters, sweep
        updateLengthCounters();
        channel1.updateSweep();
        break;
      case 7:
        // Step 7: Envelopes
        updateEnvelopes();
        break;
    }
  }

  void updateLengthCounters() {
    channel1.updateLengthCounter();
    channel2.updateLengthCounter();
    channel3.updateLengthCounter();
    channel4.updateLengthCounter();
  }

  void updateEnvelopes() {
    channel1.updateEnvelope();
    channel2.updateEnvelope();
    channel4.updateEnvelope();
    // Note: Channel 3 does not have an envelope
  }

  void mixAndQueueAudioSample() {
    // Mix audio channels and get left and right samples
    final samples = mixAudioChannels();
    int leftSample = samples[0];
    int rightSample = samples[1];

    // Queue the stereo audio sample
    queueAudioSample(leftSample, rightSample);
  }

  List<int> mixAudioChannels() {
    int left = 0;
    int right = 0;

    // Channel 1
    int ch1Output = channel1.getOutput();
    if ((nr51 & 0x01) != 0) right += ch1Output;
    if ((nr51 & 0x10) != 0) left += ch1Output;

    // Channel 2
    int ch2Output = channel2.getOutput();
    if ((nr51 & 0x02) != 0) right += ch2Output;
    if ((nr51 & 0x20) != 0) left += ch2Output;

    // Channel 3
    int ch3Output = channel3.getOutput();
    if ((nr51 & 0x04) != 0) right += ch3Output;
    if ((nr51 & 0x40) != 0) left += ch3Output;

    // Channel 4
    int ch4Output = channel4.getOutput();
    if ((nr51 & 0x08) != 0) right += ch4Output;
    if ((nr51 & 0x80) != 0) left += ch4Output;

    // Apply the master volume (leftVolume and rightVolume)
    left = (left * leftVolume) ~/ 7; // leftVolume ranges from 0 to 7
    right = (right * rightVolume) ~/ 7;

    // The Game Boy's DAC output ranges from -8 to +7
    // To output 16-bit samples, we scale the value accordingly
    // For example, scale -8 to -32768 and +7 to +32767

    // Scaling factor for 16-bit audio (from 4-bit Game Boy audio)
    const int scalingFactor = 32767 ~/ 7;

    left = (left * scalingFactor).clamp(-32768, 32767);
    right = (right * scalingFactor).clamp(-32768, 32767);

    return [left, right];
  }

  void queueAudioSample(int leftSample, int rightSample) {
    // Prepare a buffer for the stereo sample (4 bytes: 2 bytes per channel)
    final buffer = Uint8List(4);
    final byteData = buffer.buffer.asByteData();
    byteData.setInt16(0, leftSample, Endian.little);
    byteData.setInt16(2, rightSample, Endian.little);

    // Allocate memory and copy the buffer
    final bufferPtr = malloc.allocate<Uint8>(4);
    bufferPtr.asTypedList(4).setAll(0, buffer);

    // Stream the audio
    streamAudio(bufferPtr, 4);

    // Free the allocated memory
    malloc.free(bufferPtr);
  }

  Future<void> stopAudio() async {
    if (isInitialized) {
      terminateAudio();
      isInitialized = false;
    }
  }

  void reset() {
    channel1.reset();
    channel2.reset();
    channel3.reset();
    channel4.reset();
    nr50 = 0;
    nr51 = 0;
    nr52 = 0x80;
    accumulatedCycles = 0;
    frameSequencerCycles = 0;
    frameSequencer = 0;
    updateVolumes();
  }
}
