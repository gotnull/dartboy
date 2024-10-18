import 'dart:ffi';
import 'dart:typed_data';
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:ffi/ffi.dart';
import 'channel1.dart';
import 'channel2.dart';
import 'channel3.dart';
import 'channel4.dart';

// FFI setup (as before)
final DynamicLibrary audioLib = DynamicLibrary.open('libaudio.dylib');

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

late final bool Function() isAudioDeviceActive;

class Audio {
  static const int frameSequencerRate = 512; // Hz

  final int sampleRate = 44100;
  final int bufferSize = 1024;
  final int channels = 2;

  int cyclesPerSample;
  int cyclesPerFrameSequencer;

  int accumulatedCycles = 0;
  int frameSequencerCycles = 0;
  int frameSequencer = 0;
  int leftVolume = 0;
  int rightVolume = 0;

  bool isInitialized = false;

  Channel1 channel1 = Channel1();
  Channel2 channel2 = Channel2();
  Channel3 channel3 = Channel3();
  Channel4 channel4 = Channel4();

  int nr50 = 0;
  int nr51 = 0;
  int nr52 = 0x80; // Sound on by default

  Audio(int clockSpeed)
      : cyclesPerSample = clockSpeed ~/ 44100,
        cyclesPerFrameSequencer = clockSpeed ~/ frameSequencerRate;

  Future<void> init() async {
    int result = initAudio(sampleRate, channels, bufferSize);
    if (result != 0) {
      print("Error initialising audio: $result");
      return;
    }
    isInitialized = Configuration.enableAudio;
  }

  void updateClockSpeed(int newClockSpeed) {
    cyclesPerSample = newClockSpeed ~/ sampleRate;
    cyclesPerFrameSequencer = newClockSpeed ~/ frameSequencerRate;
  }

  void tick(int cycles) {
    if (!isInitialized) return;

    accumulatedCycles += cycles;
    frameSequencerCycles += cycles;

    // Ensure we produce audio samples at the correct intervals
    while (accumulatedCycles >= cyclesPerSample) {
      int sample = mixAudioChannels();
      queueAudioSample(sample);
      accumulatedCycles -= cyclesPerSample;
    }

    // Update the frame sequencer
    while (frameSequencerCycles >= cyclesPerFrameSequencer) {
      updateFrameSequencer();
      frameSequencerCycles -= cyclesPerFrameSequencer;
    }

    // Tick each channel
    channel1.tick(cycles);
    channel2.tick(cycles);
    channel3.tick(cycles);
    channel4.tick(cycles);
  }

  void updateFrameSequencer() {
    // print(
    //     "Frame Sequencer Step: $frameSequencer, Cycles: $frameSequencerCycles");

    switch (frameSequencer) {
      case 0:
      case 4:
        channel1.updateLengthCounter();
        channel2.updateLengthCounter();
        channel3.updateLengthCounter();
        channel4.updateLengthCounter();
        break;
      case 2:
      case 6:
        channel1.updateLengthCounter();
        channel2.updateLengthCounter();
        channel3.updateLengthCounter();
        channel4.updateLengthCounter();
        channel1.updateSweep();
        break;
      case 7:
        channel1.updateEnvelope();
        channel2.updateEnvelope();
        channel4.updateEnvelope();
        break;
    }

    // print(
    //   "After frame sequencer update: CH1=${channel1.enabled}, CH2=${channel2.enabled}, CH3=${channel3.enabled}, CH4=${channel4.enabled}",
    // );

    frameSequencer = (frameSequencer + 1) % 8;
  }

  void printChannelStatus() {
    print(
        "Channel 1 - Enabled: ${channel1.enabled}, DAC Enabled: ${channel1.enabled}");
    print(
        "Channel 2 - Enabled: ${channel2.enabled}, DAC Enabled: ${channel2.enabled}");
    print(
        "Channel 3 - Enabled: ${channel3.enabled}, DAC Enabled: ${channel3.enabled}");
    print(
        "Channel 4 - Enabled: ${channel4.enabled}, DAC Enabled: ${channel4.enabled}");
  }

  void updateVolumes() {
    leftVolume = (nr50 >> 4) & 0x7; // Left volume bits
    rightVolume = nr50 & 0x7; // Right volume bits
  }

  int mixAudioChannels() {
    int left = 0;
    int right = 0;

    // Mixing audio output from all channels
    if ((nr51 & 0x01) != 0) left += channel1.getOutput();
    if ((nr51 & 0x10) != 0) right += channel1.getOutput();

    if ((nr51 & 0x02) != 0) left += channel2.getOutput();
    if ((nr51 & 0x20) != 0) right += channel2.getOutput();

    if ((nr51 & 0x04) != 0) left += channel3.getOutput();
    if ((nr51 & 0x40) != 0) right += channel3.getOutput();

    if ((nr51 & 0x08) != 0) left += channel4.getOutput();
    if ((nr51 & 0x80) != 0) right += channel4.getOutput();

    // Scale left and right by the master volume (increase factor from * 4 to * 16 for more amplification)
    left = (left * ((nr50 >> 4) & 0x07) * 16) ~/ 7;
    right = (right * (nr50 & 0x07) * 16) ~/ 7;

    // Normalize left and right before mixing to avoid distortion
    return (left + right) ~/ 2;
  }

  void queueAudioSample(int sample) {
    Uint8List buffer = Uint8List(2)
      ..buffer.asByteData().setInt16(0, sample, Endian.little);
    final Pointer<Uint8> bufferPtr = malloc.allocate<Uint8>(2);
    bufferPtr.asTypedList(2).setAll(0, buffer);
    streamAudio(bufferPtr, 2);
    malloc.free(bufferPtr);

    streamAudio(bufferPtr, 2);
    // print("Queued audio sample: $sample");
  }

  String _getRegisterName(int address) {
    // print(
    //     "Writing to audio register: $registerName (${address.toRadixString(16)}) = ${value.toRadixString(16)}");

    switch (address) {
      case MemoryRegisters.nr10:
        return "nr10";
      case MemoryRegisters.nr11:
        return "nr11";
      case MemoryRegisters.nr12:
        return "nr12";
      case MemoryRegisters.nr13:
        return "nr13";
      case MemoryRegisters.nr14:
        return "nr14";
      case MemoryRegisters.nr15:
        return "nr15";
      case MemoryRegisters.waveRam:
        return "Wave RAM 00";
      case MemoryRegisters.nr21:
        return "nr21";
      case MemoryRegisters.nr22:
        return "nr22";
      case MemoryRegisters.nr23:
        return "nr23";
      case MemoryRegisters.nr24:
        return "nr24";
      case MemoryRegisters.nr30:
        return "nr30";
      case MemoryRegisters.nr31:
        return "nr31";
      case MemoryRegisters.nr32:
        return "nr32";
      case MemoryRegisters.nr33:
        return "nr33";
      case MemoryRegisters.nr34:
        return "nr34";
      case MemoryRegisters.nr41:
        return "nr41";
      case MemoryRegisters.nr42:
        return "nr42";
      case MemoryRegisters.nr43:
        return "nr43";
      case MemoryRegisters.nr44:
        return "nr44";
      case MemoryRegisters.nr50:
        return "nr50";
      case MemoryRegisters.nr51:
        return "nr51";
      case MemoryRegisters.nr52:
        return "nr52";
      default:
        return "Unknown audio register name: $address";
    }
  }

  void writeNR(int address, int value) {
    _getRegisterName(address);

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
        }
        // print("NR52 updated: ${nr52.toRadixString(16)}");
        break;
    }
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
        return nr52;
      default:
        return 0xFF;
    }
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
  }
}

class AudioInitializationException implements Exception {
  final String message;
  AudioInitializationException(this.message);
  @override
  String toString() => 'AudioInitializationException: $message';
}
