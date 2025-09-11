import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart' as audio_session;

/// iOS audio system with actual sound output
class MobileAudio {
  final Map<int, AudioPlayer> _players = {};
  final Map<int, bool> _channelEnabled = {};
  final Map<int, double> _channelFrequency = {};
  final Map<int, double> _channelVolume = {};
  
  bool _initialized = false;
  static const int sampleRate = 22050;
  
  /// Initialize iOS audio system
  Future<void> init() async {
    if (_initialized || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }
    
    try {
      // Configure iOS audio session
      final session = await audio_session.AudioSession.instance;
      await session.configure(const audio_session.AudioSessionConfiguration.music());
      
      // Initialize audio players for each Game Boy channel
      for (int i = 1; i <= 4; i++) {
        _players[i] = AudioPlayer();
        _channelEnabled[i] = false;
        _channelFrequency[i] = 440.0;
        _channelVolume[i] = 0.0;
        await _players[i]!.setReleaseMode(ReleaseMode.loop);
      }
      
      _initialized = true;
      print('iOS audio system initialized');
    } catch (e) {
      print('iOS audio init failed: $e');
      _initialized = false;
    }
  }
  
  /// Generate and play audio for a channel
  Future<void> _updateChannelAudio(int channel) async {
    if (!_initialized) return;
    
    final enabled = _channelEnabled[channel] ?? false;
    final frequency = _channelFrequency[channel] ?? 440.0;
    final volume = _channelVolume[channel] ?? 0.0;
    
    if (!enabled || volume < 0.01) {
      await _players[channel]?.stop();
      return;
    }
    
    // Generate actual tone audio file for this channel
    await _generateAndPlayTone(channel, frequency, volume);
  }
  
  /// Generate a simple tone file and play it
  Future<void> _generateAndPlayTone(int channel, double frequency, double volume) async {
    try {
      // Generate 0.5 seconds of sine wave
      const duration = 0.5;
      final samples = <int>[];
      final numSamples = (sampleRate * duration).round();
      
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final sample = sin(2 * pi * frequency * t) * volume * 32767;
        final intSample = sample.round().clamp(-32768, 32767);
        
        // Stereo 16-bit PCM
        samples.add(intSample & 0xFF);
        samples.add((intSample >> 8) & 0xFF);
        samples.add(intSample & 0xFF);
        samples.add((intSample >> 8) & 0xFF);
      }
      
      // Create WAV file
      final wavData = _createWAV(samples, sampleRate, 2, 16);
      
      // Write to temporary file
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/gb_ch$channel.wav');
      await file.writeAsBytes(wavData);
      
      // Play the generated file
      await _players[channel]?.play(DeviceFileSource(file.path), volume: volume.clamp(0.0, 0.3));
      
    } catch (e) {
      print('Failed to generate tone for channel $channel: $e');
    }
  }
  
  /// Create WAV file from PCM samples
  Uint8List _createWAV(List<int> samples, int sampleRate, int channels, int bitsPerSample) {
    final dataSize = samples.length;
    final fileSize = 36 + dataSize;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    
    final output = BytesBuilder();
    
    // WAV header
    output.add('RIFF'.codeUnits);
    output.add(_int32Bytes(fileSize));
    output.add('WAVE'.codeUnits);
    output.add('fmt '.codeUnits);
    output.add(_int32Bytes(16));
    output.add(_int16Bytes(1)); // PCM
    output.add(_int16Bytes(channels));
    output.add(_int32Bytes(sampleRate));
    output.add(_int32Bytes(byteRate));
    output.add(_int16Bytes(blockAlign));
    output.add(_int16Bytes(bitsPerSample));
    output.add('data'.codeUnits);
    output.add(_int32Bytes(dataSize));
    output.add(samples);
    
    return output.toBytes();
  }
  
  List<int> _int32Bytes(int value) => [
    value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF
  ];
  
  List<int> _int16Bytes(int value) => [
    value & 0xFF, (value >> 8) & 0xFF
  ];
  
  void setChannelFrequency(int channel, double frequency) {
    _channelFrequency[channel] = frequency.clamp(20.0, 20000.0);
    if (_channelEnabled[channel] == true) {
      _updateChannelAudio(channel);
    }
  }
  
  void setChannelVolume(int channel, double volume) {
    _channelVolume[channel] = volume.clamp(0.0, 1.0);
    if (_channelEnabled[channel] == true) {
      _updateChannelAudio(channel);
    }
  }
  
  void setChannelEnabled(int channel, bool enabled) {
    final wasEnabled = _channelEnabled[channel] ?? false;
    _channelEnabled[channel] = enabled;
    
    if (enabled != wasEnabled) {
      _updateChannelAudio(channel);
    }
  }
  
  void setChannelDuty(int channel, int duty) {
    // Placeholder - would implement square wave duty cycles
  }
  
  void setWaveformRAM(List<int> waveform) {
    // Placeholder - would implement custom waveforms
  }
  
  Future<void> startAudio() async {
    if (!_initialized) return;
    print('iOS audio started');
  }
  
  void stopAudio() {
    for (final player in _players.values) {
      player.stop();
    }
  }
  
  void dispose() {
    stopAudio();
    for (final player in _players.values) {
      player.dispose();
    }
    _initialized = false;
  }
}