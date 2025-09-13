/// Configuration contains global emulation configuration.
///
/// Type of system being emulated, debug configuration, etc.
class Configuration {
  /// Debug variable to enable and disable the background rendering.
  static bool drawBackgroundLayer = true;

  /// Debug variable to enable and disable the sprite layer rendering.
  static bool drawSpriteLayer = true;

  /// If true data sent trough the serial port will be printed on the debug terminal.
  ///
  /// Useful for debug codes printed by test ROMs.
  static bool printSerialCharacters = false;

  /// Instructions debug info and registers information is printed to the terminal if set true.
  static bool debugInstructions = false;

  /// Debug varible to enable audio.
  static bool enableAudio = true;

  /// Performance optimization - batch PPU/APU updates for better mobile performance
  static bool mobileOptimization = false; // Disable for now
  
  /// PPU update frequency when mobile optimization is enabled (cycles between updates)
  static int ppuUpdateFrequency = 1; // Back to original
  
  /// APU update frequency when mobile optimization is enabled (cycles between updates)  
  static int apuUpdateFrequency = 1; // Back to original
  
  /// Audio quality for mobile devices (reduces sample rate)
  static bool reducedAudioQuality = false;
  
  /// Skip audio samples for better performance (1 = no skip, 2 = half samples, etc)
  static int audioSampleSkip = 1; // No skipping
  
  /// Completely disable audio processing for maximum performance
  static bool disableAudioForPerformance = false;
}
