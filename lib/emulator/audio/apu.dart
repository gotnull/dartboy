import 'dart:ffi' if (dart.library.html) 'apu_web_stub.dart';
import 'dart:io' if (dart.library.html) 'platform_web_stub.dart';

import 'package:dartboy/emulator/audio/channel1.dart';
import 'package:dartboy/emulator/audio/channel2.dart';
import 'package:dartboy/emulator/audio/channel3.dart';
import 'package:dartboy/emulator/audio/channel4.dart';
import 'package:dartboy/emulator/audio/mobile_audio.dart';
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:ffi/ffi.dart' if (dart.library.html) 'apu_web_stub.dart';
import 'package:flutter/foundation.dart';

// Load the shared library with proper path handling
late final DynamicLibrary? audioLib;

DynamicLibrary? _loadAudioLibrary() {
  // Skip audio library loading on web and mobile platforms
  if (kIsWeb || (!kIsWeb && (Platform.isIOS || Platform.isAndroid))) {
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
  static const int defaultSampleRate = 44100; // SDL output rate
  static const int internalSampleRate =
      32768; // Game Boy internal rate (CPU/128)
  static const int defaultBufferSize = 1024;
  static const int defaultChannels = 2;
  static const double cpuFrequency = 4194304.0; // Game Boy CPU frequency

  final int sampleRate = 44100; // SDL output rate
  final int bufferSize = 1024;
  final int channels = 2;

  int cyclesPerSample;
  static const int cyclesPerFrameSequencer =
      8192; // 4194304 / 512 = exact timing
  int accumulatedCycles = 0;
  int frameSequencerCycles = 0;
  int frameSequencer = 0;

  // DIV-APU tracking for hardware-accurate frame sequencer
  int lastDivAPU = 0;

  // KameBoyColor m_cycles mechanism for proper channel timing
  int mCycles = 0;
  int audioCycles = 0;

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

    // Handle wave RAM reads first - always accessible regardless of APU power
    if (address >= 0x30 && address <= 0x3F) {
      return channel3.readWaveformRAM(address);
    }

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
      case 0x15: // Unused register between NR14 and NR21
        return 0xFF;
      case 0x1F: // Unused register between NR34 and NR41
        return 0xFF;
      // Unused registers between NR52 and Wave RAM
      case 0x27:
      case 0x28:
      case 0x29:
      case 0x2A:
      case 0x2B:
      case 0x2C:
      case 0x2D:
      case 0x2E:
      case 0x2F:
        return 0xFF;
      default:
        // Only print unknown register messages for addresses that should be audio registers
        if (address >= 0x10 && address <= 0x3F) {
          print("Unknown audio register read: 0x${address.toRadixString(16)}");
        }
        return 0xFF; // Return 0xFF for unmapped addresses
    }
  }

  void writeNR(int address, int value) {
    address &= 0xFFFF;

    if (address == MemoryRegisters.nr52) {
      // Handle power on/off for APU
      bool wasOn = (nr52 & 0x80) != 0;
      bool powerOn = (value & 0x80) != 0;

      if (!powerOn) {
        // Power off: reset all channels and disable APU
        if (wasOn) {
          channel1.reset();
          channel2.reset();
          channel3.reset();
          channel4.reset();
          nr50 = 0;
          nr51 = 0;
          updateVolumes();

          // Reset frame sequencer when APU is powered off
          frameSequencer = 0;
          frameSequencerCycles = 0;
        }
        nr52 = 0; // Clear NR52 except the always-on bits (set below)
      } else {
        // Power on: retain the always-on bits (4-6) in NR52
        nr52 = (value & 0x80) | 0x70; // Bits 4-6 are always 1

        // CGB behavior: Length counters are NOT reset when APU is powered on
        // This is different from DMG behavior
        // Keep existing length counter values

        // Critical: KameBoyColor sets frame_sequencer = 7 ONLY on transition from off to on
        // This timing is required for test 07 to pass
        if (!wasOn) {
          frameSequencer = 7; // next step is 0
        }
      }
      return;
    }

    // Handle wave RAM writes first - always accessible regardless of APU power
    if (address >= 0x30 && address <= 0x3F) {
      channel3.writeWaveformRAM(address, value);
      return;
    }

    // If APU is off, ignore all writes except to NR52 and wave RAM
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
        // NR52 is handled at the top of writeNR - this case should not be reached
        break;
      case 0x15: // Unused register between NR14 and NR20 - ignore writes
        break;
      case 0x1F: // Unused register between NR24 and NR30 - ignore writes
        break;
      default:
        // Only print unknown register messages for addresses that should be audio registers
        if (address >= 0x10 && address <= 0x3F) {
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
    int sampleOffset = channel3.sampleIndex >> 1;
    return channel3.waveformRAM[sampleOffset];
  }

  int writeWaveform(int addr, int data) {
    if (!channel3.enabled) {
      // Calculate offset and write data to the waveform RAM if the channel is off
      channel3.waveformRAM[addr - MemoryRegisters.waveRamStart] = data;
    } else {
      // If the channel is on, write to the current sample offset
      int sampleOffset = channel3.sampleIndex >> 1;
      channel3.waveformRAM[sampleOffset] = data;
    }
    return data;
  }

  void updateClockSpeed(int newClockSpeed) {
    cyclesPerSample = newClockSpeed ~/ defaultSampleRate;
    // cyclesPerFrameSequencer remains at 8192, as per Game Boy hardware
  }

  // Backward compatibility - uses a default DIV value if not provided
  void tick(int cycles, [int? divRegister, bool doubleSpeed = false]) {
    _tick(cycles, divRegister ?? 0, doubleSpeed);
  }

  void _tick(int cycles, int divRegister, bool doubleSpeed) {
    // Frame sequencer is clocked by a falling edge on a bit of the DIV register.
    // Bit 4 in normal speed, bit 5 in double speed.
    // CRITICAL: This must happen BEFORE checking APU power state (KameBoyColor line 927-958)
    int divBit = doubleSpeed ? 0x20 : 0x10;
    bool fell = (lastDivAPU & divBit) != 0 && (divRegister & divBit) == 0;
    lastDivAPU = divRegister;

    if (fell) {
      updateFrameSequencer();
    }

    // Now check if APU is powered on before processing audio
    if (!isInitialized || (nr52 & 0x80) == 0) return;

    accumulatedCycles += cycles;

    // Update each channel only if APU is powered on
    channel1.tick(cycles);
    channel2.tick(cycles);
    channel3.tick(cycles);
    channel4.tick(cycles);

    // Generate audio samples at exact intervals
    while (accumulatedCycles >= cyclesPerSample) {
      mixAndQueueAudioSample();
      accumulatedCycles -= cyclesPerSample;
    }
  }

  // Get current position within frame sequencer period (0-8191)
  int getFrameSequencerCycles() => frameSequencerCycles;

  // Check if we're in the first half of a length-clocking period
  bool isInFirstHalfOfLengthPeriod() {
    // Length counters are clocked on steps 0, 2, 4, 6
    // Each step is 8192/8 = 1024 cycles long
    // So we're in first half if we're in cycles 0-511 of any even step
    int stepCycles = frameSequencerCycles % 1024;
    bool isEvenStep = (frameSequencer & 1) == 0;
    return isEvenStep && stepCycles < 512;
  }

  void updateFrameSequencer() {
    // KameBoyColor architecture: INCREMENT first, THEN process (line 928-931)
    // This is critical for power-on timing: frame_sequencer = 7 means next step is 0

    // Increment frame sequencer FIRST (KameBoyColor line 928-931)
    frameSequencer = (frameSequencer + 1) % 8;

    // Set the frame sequencer value in all channels AFTER incrementing
    channel1.setFrameSequencer(frameSequencer);
    channel2.setFrameSequencer(frameSequencer);
    channel3.setFrameSequencer(frameSequencer);
    channel4.setFrameSequencer(frameSequencer);

    // Only perform actual updates if APU is powered on
    if ((nr52 & 0x80) != 0) {
      // Authentic Game Boy frame sequencer (8-step cycle):
      // Step   Length Ctr  Vol Env     Sweep
      // 0      Clock       -           -
      // 1      -           -           -
      // 2      Clock       -           Clock
      // 3      -           -           -
      // 4      Clock       -           -
      // 5      -           -           -
      // 6      Clock       -           Clock
      // 7      -           Clock       -
      switch (frameSequencer) {
        case 0: // Step 0: Length counter only
          updateLengthCounters();
          break;
        case 1: // Step 1: Nothing
          break;
        case 2: // Step 2: Length counter and sweep
          updateLengthCounters();
          channel1.updateSweep();
          break;
        case 3: // Step 3: Nothing
          break;
        case 4: // Step 4: Length counter only
          updateLengthCounters();
          break;
        case 5: // Step 5: Nothing
          break;
        case 6: // Step 6: Length counter and sweep
          updateLengthCounters();
          channel1.updateSweep();
          break;
        case 7: // Step 7: Volume envelope only
          updateEnvelopes();
          break;
      }

      // Update NR52 channel status bits
      updateNR52ChannelStatus();
    }
  }

  void updateLengthCounters() {
    channel1.updateLengthCounter();
    channel2.updateLengthCounter();
    channel3.updateLengthCounter();
    channel4.updateLengthCounter();

    // Update NR52 channel status immediately after length counter updates
    updateNR52ChannelStatus();
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
  double _lastLeftSample = 0.0;
  double _lastRightSample = 0.0;

  // Update NR52 channel status bits based on channel enabled states
  void updateNR52ChannelStatus() {
    int channelStatus = (nr52 & 0x80); // Keep APU enabled bit
    channelStatus |= 0x70; // Bits 4-6 always read as 1

    if (channel1.enabled) channelStatus |= 0x01;
    if (channel2.enabled) channelStatus |= 0x02;
    if (channel3.enabled) channelStatus |= 0x04;
    if (channel4.enabled) channelStatus |= 0x08;

    nr52 = channelStatus;
  }

  List<int> mixAudioChannels() {
    // Get raw digital channel outputs (0-15 range)
    int ch1Digital = channel1.getOutput(); // 0-15
    int ch2Digital = channel2.getOutput(); // 0-15
    int ch3Digital = channel3.getOutput(); // 0-15
    int ch4Digital = channel4.getOutput(); // 0-15

    // Optional debug output (disabled for production)
    // _debugSampleCounter++;
    // if (_debugSampleCounter % 2000 == 0 && _debugSampleCounter < 20000) {
    //   print('APU: CH1=$ch1Digital CH2=$ch2Digital CH3=$ch3Digital CH4=$ch4Digital NR51=${nr51.toRadixString(16)} NR50=${nr50.toRadixString(16)}');
    // }

    // Convert digital values through DACs (0-15) -> (-1.0 to +1.0)
    // Pan Docs: "Digital 0 maps to analog 1, digital 15 maps to analog -1" (negative slope)
    // When DAC is disabled, output is 0.0 (no signal). When DAC is on but channel off, DAC(0) = +1.0.
    double ch1Analog = channel1.dacEnabled ? (1.0 - (ch1Digital / 7.5)) : 0.0;
    double ch2Analog = channel2.dacEnabled ? (1.0 - (ch2Digital / 7.5)) : 0.0;
    double ch3Analog = channel3.dacEnabled ? (1.0 - (ch3Digital / 7.5)) : 0.0;
    double ch4Analog = channel4.dacEnabled ? (1.0 - (ch4Digital / 7.5)) : 0.0;

    // Mix channels according to NR51 panning
    double left = 0.0;
    double right = 0.0;

    // Channel routing per NR51 register
    if ((nr51 & 0x10) != 0) left += ch1Analog; // CH1 -> Left
    if ((nr51 & 0x01) != 0) right += ch1Analog; // CH1 -> Right

    if ((nr51 & 0x20) != 0) left += ch2Analog; // CH2 -> Left
    if ((nr51 & 0x02) != 0) right += ch2Analog; // CH2 -> Right

    if ((nr51 & 0x40) != 0) left += ch3Analog; // CH3 -> Left
    if ((nr51 & 0x04) != 0) right += ch3Analog; // CH3 -> Right

    if ((nr51 & 0x80) != 0) left += ch4Analog; // CH4 -> Left
    if ((nr51 & 0x08) != 0) right += ch4Analog; // CH4 -> Right

    // Apply master volume control (NR50)
    // Pan Docs: "Master volume is (volume + 1) / 8"
    left *= (leftVolume + 1) / 8.0;
    right *= (rightVolume + 1) / 8.0;

    // High-pass filter for DC removal (authentic Game Boy)
    const double alpha = 0.9996;
    _leftHighPassState = alpha * (_leftHighPassState + left - _lastLeftSample);
    _rightHighPassState =
        alpha * (_rightHighPassState + right - _lastRightSample);
    _lastLeftSample = left;
    _lastRightSample = right;

    // Convert to 16-bit samples for SDL output
    // Game Boy can have up to 4 channels mixed, so range is roughly [-4.0, +4.0]
    // Scale to 16-bit range [-32768, +32767] with headroom to prevent clipping
    const double scalingFactor = 6144.0; // 32768 / 5.33 for headroom
    int leftSample =
        (_leftHighPassState * scalingFactor).clamp(-32768, 32767).toInt();
    int rightSample =
        (_rightHighPassState * scalingFactor).clamp(-32768, 32767).toInt();

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
        if (queueSize > 65536) {
          // If more than 64KB queued - much higher threshold
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
    lastDivAPU = 0;
    mCycles = 0;
    audioCycles = 0;
    _leftHighPassState = 0.0;
    _rightHighPassState = 0.0;
    updateVolumes();
  }
}
