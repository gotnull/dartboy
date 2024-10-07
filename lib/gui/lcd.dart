import 'dart:typed_data';
import 'dart:ui';
import 'package:dartboy/emulator/graphics/ppu.dart';
import 'package:dartboy/gui/main_screen.dart';
import 'package:dartboy/utils/color_converter.dart';
import 'package:flutter/material.dart';

class LCDWidget extends StatefulWidget {
  const LCDWidget({required Key key}) : super(key: key);

  @override
  LCDState createState() => LCDState(); // Just return the state, no logic here
}

class LCDState extends State<LCDWidget> with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();

    // Safely assign MainScreen.lcdState in initState()
    MainScreen.lcdState = this;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      isComplex: true,
      willChange: true,
      painter: LCDPainter(),
    );
  }
}

/// LCD painter is used to copy the LCD data from the Gameboy PPU to the screen.
class LCDPainter extends CustomPainter {
  bool drawing = false;

  LCDPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Null safety check
    final cpu = MainScreen.emulator.cpu;
    if (cpu == null) {
      return;
    }

    drawing = true;

    int scale = 3;
    int width = PPU.lcdWidth * scale;
    int height = PPU.lcdHeight * scale;

    // Avoid repeated allocations by reusing Float32List
    Float32List points = Float32List(2);

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        Paint color = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

        // Safely access the current pixel data
        color.color = ColorConverter.toColor(
          cpu.ppu.current[(x ~/ scale) + (y ~/ scale) * PPU.lcdWidth],
        );

        // Update the points
        points[0] = x.toDouble() - width / 2.0;
        points[1] = y.toDouble() + 10;

        canvas.drawRawPoints(PointMode.points, points, color);
      }
    }

    drawing = false;
  }

  @override
  bool shouldRepaint(covariant LCDPainter oldDelegate) {
    return !drawing;
  }
}
