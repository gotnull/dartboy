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

      int width = PPU.lcdWidth;
      int height = PPU.lcdHeight;
      
      // Additional safety checks
      if (cpu.ppu.current.isEmpty || cpu.ppu.current.length < width * height) {
        // Draw green screen as fallback if buffer is invalid
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                       Paint()..color = Colors.green);
        drawing = false;
        print('PPU buffer invalid: length=${cpu.ppu.current.length}, expected=${width * height}');
        return;
      }

      // Calculate the scale factor based on the available window size
      double scaleX = size.width / width;
      double scaleY = size.height / height;

      // Use the smaller of the two scale factors to maintain aspect ratio
      double scale = scaleX < scaleY ? scaleX : scaleY;
      
      // Prevent invalid scaling
      if (scale <= 0 || !scale.isFinite) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), 
                       Paint()..color = Colors.red);
        drawing = false;
        print('Invalid scale factor: $scale, size: $size');
        return;
      }

      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          try {
            Paint paint = Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = false;

            // Safely access the current pixel data with bounds checking
            int index = x + y * width;
            if (index >= 0 && index < cpu.ppu.current.length) {
              int colorValue = cpu.ppu.current[index];
              paint.color = ColorConverter.toColor(colorValue);
            } else {
              paint.color = const Color(0xFFFF00FF); // Debug magenta color for invalid pixels
            }

            // Draw each pixel as a scaled-up rectangle based on the window size
            Rect pixelRect = Rect.fromLTWH(
              (x * scale).toDouble(),
              (y * scale).toDouble(),
              scale.toDouble(),
              scale.toDouble(),
            );

            canvas.drawRect(pixelRect, paint);
          } catch (e) {
            // If individual pixel fails, continue with next one
            print('Pixel draw error at ($x,$y): $e');
          }
        }
      }

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
