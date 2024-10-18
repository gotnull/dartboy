import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'gui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the window manager
  await windowManager.ensureInitialized();

  // Set the minimum window size before running the app
  await setWindowSize();

  // Set the window title
  windowManager.setTitle('Dart Boy');

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
      title: 'GBC',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(title: 'GBC', key: Key("gbc")),
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      showSemanticsDebugger: false,
      debugShowMaterialGrid: false,
    );
  }
}
