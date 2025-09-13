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
  static final Map<int, Paint> _paintCache = {};

  LCDPainter();

  @override
  void paint(Canvas canvas, Size size) {
    try {
      // Null safety check
      final cpu = MainScreen.emulator.cpu;
      if (cpu == null) {
        // Draw black screen if no CPU
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                       Paint()..color = Colors.black);
        return;
      }

      drawing = true;

      const int width = PPU.lcdWidth;
      const int height = PPU.lcdHeight;
      
      // Additional safety checks
      if (cpu.ppu.current.isEmpty || cpu.ppu.current.length < width * height) {
        // Draw green screen as fallback if buffer is invalid
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                       Paint()..color = Colors.green);
        drawing = false;
        return;
      }

      // Calculate the scale factor based on the available window size
      double scaleX = size.width / width;
      double scaleY = size.height / height;
      double scale = scaleX < scaleY ? scaleX : scaleY;
      
      // Prevent invalid scaling
      if (scale <= 0 || !scale.isFinite) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                       Paint()..color = Colors.red);
        drawing = false;
        return;
      }

      // Center the image
      final double scaledWidth = width * scale;
      final double scaledHeight = height * scale;
      final double offsetX = (size.width - scaledWidth) / 2;
      final double offsetY = (size.height - scaledHeight) / 2;

      // Group pixels by color for batch drawing
      final Map<int, List<Rect>> colorGroups = {};
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int index = x + y * width;
          if (index >= 0 && index < cpu.ppu.current.length) {
            int colorValue = cpu.ppu.current[index];
            
            // Calculate scaled pixel position
            double pixelX = offsetX + x * scale;
            double pixelY = offsetY + y * scale;
            
            Rect pixelRect = Rect.fromLTWH(pixelX, pixelY, scale, scale);
            
            colorGroups.putIfAbsent(colorValue, () => []).add(pixelRect);
          }
        }
      }

      // Draw all rectangles of the same color at once
      colorGroups.forEach((colorValue, rects) {
        Paint paint = _paintCache.putIfAbsent(colorValue, () => Paint()
          ..style = PaintingStyle.fill
          ..color = ColorConverter.toColor(colorValue)
          ..isAntiAlias = false);

        for (Rect rect in rects) {
          canvas.drawRect(rect, paint);
        }
      });

      drawing = false;
    } catch (e) {
      // Catch any other rendering errors
      print('LCD render error: $e');
      drawing = false;
      // Draw error screen
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                     Paint()..color = Colors.orange);
    }
  }


  @override
  bool shouldRepaint(covariant LCDPainter oldDelegate) {
    return !drawing;
  }
}
