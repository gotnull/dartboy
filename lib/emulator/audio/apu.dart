import 'dart:ffi';
import 'dart:io';

import 'package:dartboy/emulator/audio/channel1.dart';
import 'package:dartboy/emulator/audio/channel2.dart';
import 'package:dartboy/emulator/audio/channel3.dart';
import 'package:dartboy/emulator/audio/channel4.dart';
import 'package:dartboy/emulator/audio/mobile_audio.dart';
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// Load the shared library with proper path handling
late final DynamicLibrary? audioLib;

DynamicLibrary? _loadAudioLibrary() {
  // Skip audio library loading on mobile platforms
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    return null;
  }

  try {
    // Try loading from the app bundle first (for production builds)
    return DynamicLibrary.open('libaudio.dylib');
  } catch (e) {
    try {
      // Try loading from the macos directory (for development)
      return DynamicLibrary.open('./macos/libaudio.dylib');
    } catch (e) {
      try {
        // Try loading from the build directory
        return DynamicLibrary.open(
            './build/macos/Build/Products/Debug/dartboy.app/Contents/Frameworks/libaudio.dylib');
      } catch (e) {
        try {
          // Try with full path to macos directory
          return DynamicLibrary.open(
              '/Users/fulvio/development/dartboy/macos/libaudio.dylib');
        } catch (e) {
          // Final fallback - return null for graceful degradation
          print(
              'Warning: Failed to load libaudio.dylib. Audio will be disabled.');
          return null;
        }
      }
    }
  }
}

// FFI definitions for the functions in the shared library
typedef InitAudioNative = Int32 Function(
    Int32 sampleRate, Int32 channels, Int32 bufferSize);
typedef InitAudioDart = int Function(
    int sampleRate, int channels, int bufferSize);

typedef StreamAudioNative = Void Function(Pointer<Uint8> buffer, Int32 length);
typedef StreamAudioDart = void Function(Pointer<Uint8> buffer, int length);

typedef TerminateAudioNative = Void Function();
typedef TerminateAudioDart = void Function();

// Initialize the library
void _initializeAudioLib() {
  if (!_audioLibInitialized) {
    audioLib = _loadAudioLibrary();
    _audioLibInitialized = true;
  }
}

bool _audioLibInitialized = false;

InitAudioDart? _initAudio;
InitAudioDart get initAudio {
  _initializeAudioLib();
  if (audioLib == null) {
    return _initAudio ??= (int sampleRate, int channels, int bufferSize) => -1;
  }
  try {
    return _initAudio ??= audioLib!
        .lookup<NativeFunction<InitAudioNative>>('init_audio')
        .asFunction();
  } catch (e) {
    // Return dummy function if audio library loading fails
    return _initAudio ??= (int sampleRate, int channels, int bufferSize) => -1;
  }
}

StreamAudioDart? _streamAudio;
StreamAudioDart get streamAudio {
  _initializeAudioLib();
  if (audioLib == null) {
    return _streamAudio ??=
        (Pointer<Uint8> buffer, int length) {}; // Dummy function
  }
  try {
    return _streamAudio ??= audioLib!
        .lookup<NativeFunction<StreamAudioNative>>('stream_audio')
        .asFunction();
  } catch (e) {
    return _streamAudio ??=
        (Pointer<Uint8> buffer, int length) {}; // Dummy function
  }
}

TerminateAudioDart? _terminateAudio;
TerminateAudioDart get terminateAudio {
  _initializeAudioLib();
  if (audioLib == null) {
    return _terminateAudio ??= () {}; // Dummy function
  }
  try {
    return _terminateAudio ??= audioLib!
        .lookup<NativeFunction<TerminateAudioNative>>('terminate_audio')
        .asFunction();
  } catch (e) {
    return _terminateAudio ??= () {}; // Dummy function
  }
}

// Additional FFI functions for audio management
typedef GetQueuedAudioSizeNative = Uint32 Function();
typedef GetQueuedAudioSizeDart = int Function();

typedef ClearQueuedAudioNative = Void Function();
typedef ClearQueuedAudioDart = void Function();

GetQueuedAudioSizeDart? _getQueuedAudioSize;
GetQueuedAudioSizeDart get getQueuedAudioSize {
  _initializeAudioLib();
  if (audioLib == null) {
    return _getQueuedAudioSize ??= () => 0; // Dummy function
  }
  try {
    return _getQueuedAudioSize ??= audioLib!
        .lookup<NativeFunction<GetQueuedAudioSizeNative>>(
            'get_queued_audio_size')
        .asFunction();
  } catch (e) {
    return _getQueuedAudioSize ??= () => 0; // Dummy function
  }
}

ClearQueuedAudioDart? _clearQueuedAudio;
ClearQueuedAudioDart get clearQueuedAudio {
  _initializeAudioLib();
  if (audioLib == null) {
    return _clearQueuedAudio ??= () {}; // Dummy function
  }
  try {
    return _clearQueuedAudio ??= audioLib!
        .lookup<NativeFunction<ClearQueuedAudioNative>>('clear_queued_audio')
        .asFunction();
  } catch (e) {
    return _clearQueuedAudio ??= () {}; // Dummy function
  }
}

class APU {
  static const int frameSequencerRate = 512; // Hz
  static const int defaultSampleRate = 32768; // Authentic Game Boy rate (CPU/128)
  static const int defaultBufferSize = 1024;
  static const int defaultChannels = 2;

  final int sampleRate = 32768; // Much closer to original Game Boy
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

  // Mobile audio system
  MobileAudio? _mobileAudio;
  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  
  // Audio performance optimization
  int _audioSampleCounter = 0;

  APU(clockSpeed) : cyclesPerSample = clockSpeed ~/ defaultSampleRate {
    if (_isMobile) {
      _mobileAudio = MobileAudio();
    }
  }

  Future<void> init() async {
    if (_isMobile) {
      print('APU: Initializing MobileAudio...');
      await _mobileAudio?.init();
      print('APU: MobileAudio initialized.');
      await _mobileAudio?.startAudio();
      print('APU: MobileAudio started.');
      isInitialized = Configuration.enableAudio;
    } else {
      int result = initAudio(sampleRate, channels, bufferSize);
      if (result != 0) {
        // Handle initialization error if necessary
      }
      isInitialized = Configuration.enableAudio;
    }
  }

  // Update left and right channel volumes based on NR50 register
  void updateVolumes() {
    leftVolume = (nr50 >> 4) & 0x07; // Left volume is controlled by bits 4-6
    rightVolume = nr50 & 0x07; // Right volume is controlled by bits 0-2
  }

  int readNR(int address) {
    address &= 0xFFFF;

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
        int channelStatus = 0;
        if (channel1.enabled) channelStatus |= 0x01;
        if (channel2.enabled) channelStatus |= 0x02;
        if (channel3.enabled) channelStatus |= 0x04;
        if (channel4.enabled) channelStatus |= 0x08;
        return (nr52 & 0x80) |
            0x70 |
            channelStatus; // Bit 7 = power, bits 4-6 = 1, bits 0-3 = channel status
      case 0xFF15: // Unused register between NR14 and NR20
        return 0xFF;
      case 0xFF1F: // Unused register between NR24 and NR30
        return 0xFF;
      default:
        // Only print unknown register messages for addresses that should be audio registers
        if (address >= 0xFF10 && address <= 0xFF3F) {
          print("Unknown audio register read: 0x${address.toRadixString(16)}");
        }
        return 0xFF; // Return 0xFF for unmapped addresses
    }
  }

  void writeNR(int address, int value) {
    address &= 0xFFFF;

    if (address == MemoryRegisters.nr52) {
      // Handle power on/off for APU
      bool powerOn = (value & 0x80) != 0;
      if (!powerOn) {
        // Power off: reset all channels and disable APU
        channel1.reset();
        channel2.reset();
        channel3.reset();
        channel4.reset();
        nr50 = 0;
        nr51 = 0;
        nr52 = 0; // Clear NR52 except the always-on bits (set below)
        updateVolumes();

        // Reset frame sequencer when APU is powered off
        frameSequencer = 0;
        frameSequencerCycles = 0;
      } else {
        // Power on: retain the always-on bits (4-6) in NR52
        nr52 = (value & 0x80) | 0x70; // Bits 4-6 are always 1
      }
      return;
    }

    // If APU is off, ignore all writes except to NR52
    if ((nr52 & 0x80) == 0) return;

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
      case 0xFF15: // Unused register between NR14 and NR20 - ignore writes
        break;
      case 0xFF1F: // Unused register between NR24 and NR30 - ignore writes
        break;
      default:
        // Only print unknown register messages for addresses that should be audio registers
        if (address >= 0xFF10 && address <= 0xFF3F) {
          print(
              "Unknown audio register write: 0x${address.toRadixString(16)} = $value");
        }
    }
  }

  int readWaveform(int addr) {
    if (!channel3.enabled) {
      // Calculate the offset from the base address for the waveform RAM and return the value
      return channel3.waveformRAM[addr - MemoryRegisters.waveRamStart];
    }

    // If channel is on, return the current sample being played
    int sampleOffset = channel3.waveformIndex >> 1;
    return channel3.waveformRAM[sampleOffset];
  }

  int writeWaveform(int addr, int data) {
    if (!channel3.enabled) {
      // Calculate offset and write data to the waveform RAM if the channel is off
      channel3.waveformRAM[addr - MemoryRegisters.waveRamStart] = data;
    } else {
      // If the channel is on, write to the current sample offset
      int sampleOffset = channel3.waveformIndex >> 1;
      channel3.waveformRAM[sampleOffset] = data;
    }
    return data;
  }

  void updateClockSpeed(int newClockSpeed) {
    cyclesPerSample = newClockSpeed ~/ sampleRate;
    // cyclesPerFrameSequencer remains at 8192, as per Game Boy hardware
  }

  void tick(int cycles) {
    if (!isInitialized || (nr52 & 0x80) == 0) return;

    accumulatedCycles += cycles;
    frameSequencerCycles += cycles;

    // Update each channel only if APU is powered on
    channel1.tick(cycles);
    channel2.tick(cycles);
    channel3.tick(cycles);
    channel4.tick(cycles);

    // Update frame sequencer every 8192 CPU cycles
    while (frameSequencerCycles >= cyclesPerFrameSequencer) {
      updateFrameSequencer();
      frameSequencerCycles -= cyclesPerFrameSequencer;
    }

    // Generate audio samples at the correct intervals (optimized for mobile)
    if (accumulatedCycles >= cyclesPerSample) {
      int samplesToGenerate = accumulatedCycles ~/ cyclesPerSample;
      if (samplesToGenerate > 0) {
        // Limit to prevent audio buffer overflow and reduce processing load
        samplesToGenerate = samplesToGenerate.clamp(1, 2); // Reduce max samples per tick
        for (int i = 0; i < samplesToGenerate; i++) {
          mixAndQueueAudioSample();
        }
        accumulatedCycles -= samplesToGenerate * cyclesPerSample;
      }
    }
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
      case 2:
      case 4:
      case 6:
        updateLengthCounters();
        if (frameSequencer == 2 || frameSequencer == 6) channel1.updateSweep();
        break;
      case 1:
        // Step 1: Nothing
        break;
      case 3:
        // Step 3: Nothing
        break;
      case 5:
        // Step 5: Nothing
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

    if (_isMobile) {
      // Update mobile audio with channel states
      _updateMobileAudio(leftSample, rightSample);
    } else {
      // Queue the stereo audio sample for desktop
      queueAudioSample(leftSample, rightSample);
    }
  }

  void _updateMobileAudio(int leftSample, int rightSample) {
    if (_mobileAudio == null) return;

    // Completely disable audio processing if enabled for performance testing
    if (Configuration.disableAudioForPerformance) {
      return;
    }

    // Skip samples for better performance if mobile optimization is enabled
    if (Configuration.mobileOptimization && Configuration.reducedAudioQuality) {
      _audioSampleCounter++;
      if (_audioSampleCounter % Configuration.audioSampleSkip != 0) {
        return; // Skip this sample
      }
    }

    _mobileAudio!.queueSample(leftSample, rightSample);
  }

  // High-pass filter state for DC blocking
  double _leftHighPassState = 0.0;
  double _rightHighPassState = 0.0;

  List<int> mixAudioChannels() {
    double left = 0.0;
    double right = 0.0;

    // Channel 1 (pulse with sweep)
    double ch1Output = channel1.getOutput().toDouble();
    if ((nr51 & 0x01) != 0) right += ch1Output;
    if ((nr51 & 0x10) != 0) left += ch1Output;

    // Channel 2 (pulse)
    double ch2Output = channel2.getOutput().toDouble();
    if ((nr51 & 0x02) != 0) right += ch2Output;
    if ((nr51 & 0x20) != 0) left += ch2Output;

    // Channel 3 (wave)
    double ch3Output = channel3.getOutput().toDouble();
    if ((nr51 & 0x04) != 0) right += ch3Output;
    if ((nr51 & 0x40) != 0) left += ch3Output;

    // Channel 4 (noise)
    double ch4Output = channel4.getOutput().toDouble();
    if ((nr51 & 0x08) != 0) right += ch4Output;
    if ((nr51 & 0x80) != 0) left += ch4Output;

    // Apply the master volume (0-7 range) - correct Game Boy mixing
    left = (left * (leftVolume + 1)) / 8.0;
    right = (right * (rightVolume + 1)) / 8.0;

    // Apply high-pass filter for DC blocking (Game Boy authentic)
    const double alpha = 0.999; // ~5Hz cutoff for authentic Game Boy sound
    double leftFiltered = left - _leftHighPassState;
    _leftHighPassState += leftFiltered * (1 - alpha);
    double rightFiltered = right - _rightHighPassState;
    _rightHighPassState += rightFiltered * (1 - alpha);

    // Minimal low-pass filtering to preserve authentic Game Boy sound
    const double lowPassAlpha = 0.95; // Much less aggressive filtering
    leftFiltered *= lowPassAlpha;
    rightFiltered *= lowPassAlpha;

    // Scale to 16-bit range with authentic Game Boy characteristics
    // Game Boy DAC outputs values from -15 to +15, scale authentically
    const double scalingFactor = 512.0; // More authentic Game Boy volume levels

    int leftSample =
        (leftFiltered * scalingFactor).clamp(-32768, 32767).toInt();
    int rightSample =
        (rightFiltered * scalingFactor).clamp(-32768, 32767).toInt();

    return [leftSample, rightSample];
  }

  // Pre-allocated buffer for audio samples to avoid malloc/free overhead
  static final Uint8List _audioBuffer = Uint8List(4);
  static final ByteData _audioByteData = _audioBuffer.buffer.asByteData();
  static Pointer<Uint8>? _audioBufferPtr;
  static int _queueSizeCheckCounter = 0;

  void queueAudioSample(int leftSample, int rightSample) {
    // Initialize buffer pointer once
    _audioBufferPtr ??= malloc.allocate<Uint8>(4);

    // Check audio queue size occasionally to prevent excessive latency (every 100 samples)
    if (++_queueSizeCheckCounter >= 100) {
      _queueSizeCheckCounter = 0;
      try {
        int queueSize = getQueuedAudioSize();
        if (queueSize > 16384) {
          // If more than 16KB queued
          clearQueuedAudio(); // Clear queue to reduce latency
        }
      } catch (e) {
        // If audio monitoring fails, continue without it
      }
    }

    // Use pre-allocated buffer to avoid memory allocation overhead
    _audioByteData.setInt16(0, leftSample, Endian.little);
    _audioByteData.setInt16(2, rightSample, Endian.little);

    // Copy to native memory buffer
    _audioBufferPtr!.asTypedList(4).setAll(0, _audioBuffer);

    // Stream the audio
    streamAudio(_audioBufferPtr!, 4);
  }

  Future<void> stopAudio() async {
    if (isInitialized) {
      if (_isMobile) {
        print('APU: Stopping MobileAudio...');
        _mobileAudio?.stopAudio();
        print('APU: MobileAudio stopped.');
      } else {
        terminateAudio();
      }
      isInitialized = false;
    }

    // Free the audio buffer when stopping
    if (_audioBufferPtr != null) {
      malloc.free(_audioBufferPtr!);
      _audioBufferPtr = null;
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
    _leftHighPassState = 0.0;
    _rightHighPassState = 0.0;
    updateVolumes();
  }
}
