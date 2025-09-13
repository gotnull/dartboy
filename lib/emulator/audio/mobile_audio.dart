import 'dart:async';
import 'dart:io';

import 'dart:typed_data';
import 'dart:math';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter_sound/flutter_sound.dart';

/// iOS audio system with actual sound output
class MobileAudio {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  StreamController<Uint8List>?
      _audioStreamController; // Single stream controller

  bool _initialized = false;
  static const int sampleRate = 44100;

  int _debugPrintCounter = 0;
  DateTime? _debugPrintStartTime;
  static const int _debugPrintDurationSeconds = 2;

  /// Initialize iOS audio system
  Future<void> init() async {
    if (_initialized || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }

    try {
      // Configure iOS audio session
      final session = await audio_session.AudioSession.instance;
      await session
          .configure(const audio_session.AudioSessionConfiguration.music());

      // Open FlutterSoundPlayer
      await _mPlayer!.openPlayer();
      print('FlutterSoundPlayer opened.');

      // Initialize a single audio stream controller and start player
      _audioStreamController = StreamController<Uint8List>();
      await _mPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 2, // Stereo
        sampleRate: sampleRate,
        bufferSize: 4096, // Example buffer size
        interleaved: true, // Stereo data is typically interleaved
      );
      print('Stream player started for mixed audio.');

      _initialized = true;
      print('iOS audio system initialized');
    } catch (e) {
      print('iOS audio init failed: $e');
      _initialized = false;
    }
  }

  // For testing purposes: generate a simple sine wave
  double _sinePhase = 0.0;
  static const double _sineFrequency = 440.0; // Hz
  static const double _sineAmplitude = 0.5; // 0.0 to 1.0

  void queueSample(int leftSample, int rightSample) {
    if (!_initialized) return;

    // --- START TEST SINE WAVE GENERATION ---
    final ByteData byteData = ByteData(4); // 2 samples * 2 bytes/sample
    final double sampleValue = _sineAmplitude * sin(_sinePhase);
    final int intSample =
        (sampleValue * 32767).toInt(); // Scale to 16-bit signed range

    byteData.setInt16(0, intSample, Endian.little);
    byteData.setInt16(2, intSample, Endian.little); // Stereo

    _sinePhase += (2 * pi * _sineFrequency) / sampleRate;
    if (_sinePhase > 2 * pi) _sinePhase -= 2 * pi;
    // --- END TEST SINE WAVE GENERATION ---

    _audioStreamController!.add(byteData.buffer.asUint8List());

    // Limit debug prints to the first 5 seconds
    _debugPrintStartTime ??= DateTime.now();
    if (DateTime.now().difference(_debugPrintStartTime!).inSeconds <
        _debugPrintDurationSeconds) {
      print(
          'Queued sample: L=$leftSample, R=$rightSample, isPlaying: ${_mPlayer!.isPlaying}');
    } else if (_debugPrintCounter == 0) {
      print(
          'Queued sample prints limited to first $_debugPrintDurationSeconds seconds.');
      _debugPrintCounter++; // Ensure this message prints only once
    }
  }

  Future<void> startAudio() async {
    if (!_initialized) return;
    print('MobileAudio startAudio called.');
    // Audio streams are already started in init()
  }

  void stopAudio() {
    if (_mPlayer!.isPlaying) {
      _mPlayer!.stopPlayer();
    }
    _audioStreamController?.close(); // Close the single stream controller
    _audioStreamController = null; // Clear the reference
  }

  void dispose() {
    stopAudio();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    _initialized = false;
  }
}
