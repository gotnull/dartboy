import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter_sound/flutter_sound.dart';

/// iOS audio system with actual sound output
class MobileAudio {
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  StreamController<Uint8List>?
      _audioStreamController; // Single stream controller

  bool _initialized = false;
  static const int sampleRate = 44100;
  static const int bufferSize = 1024; // Smaller buffer for lower latency

  int _debugPrintCounter = 0;
  DateTime? _debugPrintStartTime;
  static const int _debugPrintDurationSeconds = 2;
  
  // Buffer for accumulating samples before sending to stream
  final List<int> _sampleBuffer = [];
  static const int _bufferThreshold = 512; // Back to original size
  

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

    // More efficient: Add samples individually instead of creating list
    _sampleBuffer.add(leftSample);
    _sampleBuffer.add(rightSample);
    
    // Send buffer when it reaches threshold
    if (_sampleBuffer.length >= _bufferThreshold) {
      _flushSampleBuffer();
    }

    // Reduce debug prints frequency for better performance
    if (_debugPrintCounter % 1000 == 0 && _debugPrintCounter < 5000) {
      _debugPrintStartTime ??= DateTime.now();
      if (DateTime.now().difference(_debugPrintStartTime!).inSeconds < _debugPrintDurationSeconds) {
        print('Audio buffer: ${_sampleBuffer.length}/$_bufferThreshold, playing: ${_mPlayer!.isPlaying}');
      }
    }
    _debugPrintCounter++;
  }

  void _flushSampleBuffer() {
    if (_sampleBuffer.isEmpty) return;
    
    // Convert int samples to bytes
    final ByteData byteData = ByteData(_sampleBuffer.length * 2); // 2 bytes per sample
    for (int i = 0; i < _sampleBuffer.length; i++) {
      byteData.setInt16(i * 2, _sampleBuffer[i], Endian.little);
    }
    
    _audioStreamController!.add(byteData.buffer.asUint8List());
    _sampleBuffer.clear();
  }

  Future<void> startAudio() async {
    if (!_initialized) return;
    print('MobileAudio startAudio called.');
    // Audio streams are already started in init()
  }

  void stopAudio() {
    // Flush any remaining samples before stopping
    _flushSampleBuffer();
    
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
