import 'package:flutter/material.dart';

/// Util to convert between flutter colors and RGB colors.
class ColorConverter {
  static int toRGB(Color color) {
    return ((color.r * 255.0).round() & 0xFF) << 16 |
        ((color.g * 255.0).round() & 0xFF) << 8 |
        ((color.b * 255.0).round() & 0xFF);
  }

  static Color toColor(int rgb) {
    return Color(0xFF000000 | rgb);
  }
}
