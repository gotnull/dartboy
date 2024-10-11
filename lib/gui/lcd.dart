import 'package:dartboy/emulator/graphics/ppu.dart';
import 'package:dartboy/gui/main_screen.dart';
import 'package:dartboy/utils/color_converter.dart';
import 'package:flutter/material.dart';

class LCDWidget extends StatefulWidget {
  const LCDWidget({required Key key}) : super(key: key);

  @override
  LCDState createState() => LCDState();
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

    int scale = 4; // Scale factor for larger display
    int width = PPU.lcdWidth;
    int height = PPU.lcdHeight;

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        Paint paint = Paint()..style = PaintingStyle.fill;

        // Safely access the current pixel data
        int colorValue = cpu.ppu.current[x + y * width];
        paint.color = ColorConverter.toColor(colorValue);

        // Draw each pixel as a scaled-up rectangle
        Rect pixelRect = Rect.fromLTWH(
          (x * scale).toDouble(),
          (y * scale).toDouble(),
          scale.toDouble(),
          scale.toDouble(),
        );

        canvas.drawRect(pixelRect, paint);
      }
    }

    drawing = false;
  }

  @override
  bool shouldRepaint(covariant LCDPainter oldDelegate) {
    return !drawing;
  }
}
