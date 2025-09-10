import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'gui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize window manager on desktop platforms
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    try {
      await windowManager.ensureInitialized();
      await setWindowSize();
      await windowManager.setTitle('Dart Boy');
    } catch (e) {
      print('Window manager not available on this platform: $e');
    }
  }

  runApp(const DartBoy());
}

Future<void> setWindowSize() async {
  // Set the minimum size for the window to prevent resizing
  await windowManager.setMinimumSize(
    const Size(1300, 900),
  );

  // Optionally, set an initial window size to match the minimum size
  await windowManager.setSize(
    const Size(1300, 900),
  );
}

class DartBoy extends StatelessWidget {
  const DartBoy({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dart Boy',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(title: 'Dart Boy', key: Key("dartBoy")),
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      showSemanticsDebugger: false,
      debugShowMaterialGrid: false,
    );
  }
}
