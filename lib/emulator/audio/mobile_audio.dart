import 'dart:async';
import 'dart:io' if (dart.library.html) 'platform_web_stub.dart';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// iOS audio system with actual sound output
class MobileAudio {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  StreamController<Uint8List>?
      _audioStreamController; // Single stream controller

  bool _initialized = false;
  int? _androidApiLevel;
  static const int sampleRate = 44100; // Standard audio output rate
  static const int bufferSize = 2048; // Optimal buffer for high quality audio

  int _debugPrintCounter = 0;

  // Pre-allocated buffer for better performance
  static const int _maxBufferSize = 4096;
  final Uint8List _audioBuffer = Uint8List(_maxBufferSize);
  int _bufferIndex = 0;
  static const int _flushThreshold = 2048; // Flush when buffer is half full

  /// Initialize iOS audio system
  Future<void> init() async {
    if (_initialized || (kIsWeb || (!Platform.isIOS && !Platform.isAndroid))) {
      return;
    }

    try {
      // Get Android API level for proper audio configuration
      if (!kIsWeb && Platform.isAndroid) {
        await _getAndroidApiLevel();
      }

      // Configure audio session with proper API level awareness
      final session = await audio_session.AudioSession.instance;

      if (!kIsWeb && Platform.isAndroid) {
        await _configureAndroidAudio(session);
      } else {
        // iOS configuration - always use music config
        await session
            .configure(const audio_session.AudioSessionConfiguration.music());
      }

      // Open FlutterSoundPlayer
      await _mPlayer!.openPlayer();
      print('FlutterSoundPlayer opened.');

      // Initialize a single audio stream controller and start player
      _audioStreamController = StreamController<Uint8List>();

      // Initialize with full quality audio
      await _mPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 2, // Stereo
        sampleRate: sampleRate,
        bufferSize: bufferSize,
        interleaved: true, // Stereo data is typically interleaved
      );

      // Connect the stream controller to the player
      _audioStreamController!.stream.listen((data) {
        _mPlayer!.feedUint8FromStream(data);
      });
      print('Stream player started for mixed audio.');

      _initialized = true;
      print('iOS audio system initialized');
    } catch (e) {
      print('iOS audio init failed: $e');
      _initialized = false;
    }
  }

  void queueSample(int leftSample, int rightSample) {
    if (!_initialized) return;

    // Check if buffer has space (4 bytes per stereo sample)
    if (_bufferIndex + 4 > _maxBufferSize) {
      _flushAudioBuffer();
    }

    // Write directly to pre-allocated buffer (little endian 16-bit)
    _audioBuffer[_bufferIndex] = leftSample & 0xFF;
    _audioBuffer[_bufferIndex + 1] = (leftSample >> 8) & 0xFF;
    _audioBuffer[_bufferIndex + 2] = rightSample & 0xFF;
    _audioBuffer[_bufferIndex + 3] = (rightSample >> 8) & 0xFF;
    _bufferIndex += 4;

    // Flush when we reach the threshold for smoother playback
    if (_bufferIndex >= _flushThreshold) {
      _flushAudioBuffer();
    }

    // Minimal debug output
    if (_debugPrintCounter % 5000 == 0 && _debugPrintCounter < 10000) {
      print(
          'Audio buffer: $_bufferIndex/$_maxBufferSize bytes, playing: ${_mPlayer!.isPlaying}');
    }
    _debugPrintCounter++;
  }

  void _flushAudioBuffer() {
    if (_bufferIndex == 0) return;

    // Send only the filled portion of the buffer
    final Uint8List audioData =
        Uint8List.fromList(_audioBuffer.take(_bufferIndex).toList());
    _audioStreamController!.add(audioData);

    // Reset buffer index
    _bufferIndex = 0;
  }

  Future<void> startAudio() async {
    if (!_initialized) return;
    print('MobileAudio startAudio called.');
    // Audio streams are already started in init()
  }

  void stopAudio() {
    // Flush any remaining samples before stopping
    _flushAudioBuffer();

    if (_mPlayer!.isPlaying) {
      _mPlayer!.stopPlayer();
    }
    _audioStreamController?.close(); // Close the single stream controller
    _audioStreamController = null; // Clear the reference
  }

  Future<void> _getAndroidApiLevel() async {
    try {
      const platform = MethodChannel('flutter.dev/device_info');
      final int apiLevel = await platform.invokeMethod('getAndroidApiLevel');
      _androidApiLevel = apiLevel;
      print('Android API Level: $apiLevel');
    } catch (e) {
      print('Could not get Android API level: $e');
      _androidApiLevel = null;
    }
  }

  Future<void> _configureAndroidAudio(
      audio_session.AudioSession session) async {
    // Samsung S5 typically runs Android 6.0 (API 23) or lower
    // Samsung S10 runs Android 9+ (API 28+)

    if (_androidApiLevel != null && _androidApiLevel! >= 26) {
      // Android 8.0+ (API 26+) - Full feature set
      await session
          .configure(const audio_session.AudioSessionConfiguration.music());
      print('Using modern audio configuration (API $_androidApiLevel)');
    } else {
      // Android 7.1 and below - Use basic configuration
      await session.configure(const audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            audio_session.AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: audio_session.AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            audio_session.AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.music,
          flags: audio_session.AndroidAudioFlags.none,
          usage: audio_session.AndroidAudioUsage.game,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      print(
          'Using compatibility audio configuration (API ${_androidApiLevel ?? "unknown"})');
    }
  }

  void dispose() {
    stopAudio();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    _initialized = false;
  }
}
