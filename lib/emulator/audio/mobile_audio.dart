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
  static const int bufferSize = 2048; // Larger buffer for smoother playback

  int _debugPrintCounter = 0;
  
  // Pre-allocated buffer for better performance
  static const int _maxBufferSize = 4096;
  final Uint8List _audioBuffer = Uint8List(_maxBufferSize);
  int _bufferIndex = 0;
  static const int _flushThreshold = 2048; // Flush when buffer is half full
  

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
      print('Audio buffer: $_bufferIndex/$_maxBufferSize bytes, playing: ${_mPlayer!.isPlaying}');
    }
    _debugPrintCounter++;
  }

  void _flushAudioBuffer() {
    if (_bufferIndex == 0) return;
    
    // Send only the filled portion of the buffer
    final Uint8List audioData = Uint8List.fromList(_audioBuffer.take(_bufferIndex).toList());
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

  void dispose() {
    stopAudio();
    _mPlayer!.closePlayer();
    _mPlayer = null;
    _initialized = false;
  }
}
