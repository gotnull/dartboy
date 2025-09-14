import 'package:flutter/material.dart';
import 'gui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DartBoy());
}

class DartBoy extends StatelessWidget {
  const DartBoy({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DartBoy',
      theme: _buildTheme(),
      home: const MainScreen(title: 'DartBoy', key: Key("dartBoy")),
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      showSemanticsDebugger: false,
      debugShowMaterialGrid: false,
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF007AFF),
        secondary: Color(0xFF5AC8FA),
        tertiary: Color(0xFFFF9500),
        surface: Color(0xFF1C1C1E),
        surfaceContainerHighest: Color(0xFF2C2C2E),
        onSurface: Color(0xFFFFFFFF),
        onSurfaceVariant: Color(0xFF8E8E93),
      ),
      fontFamily: '.SF Pro Display',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFFFFF),
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFFFFF),
          letterSpacing: -0.3,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFFFFF),
          letterSpacing: -0.2,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: Color(0xFFFFFFFF),
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: Color(0xFF8E8E93),
        ),
        labelLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Color(0xFF007AFF),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}
