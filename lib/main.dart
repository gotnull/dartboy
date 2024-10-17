import 'package:desktop_window/desktop_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'gui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the window manager
  await windowManager.ensureInitialized();

  windowManager.setTitle('Dart Boy');

  runApp(const DartBoy());

  setWindowSize();
}

Future<void> setWindowSize() async {
  // Set the minimum size for the window to prevent resizing
  await DesktopWindow.setMinWindowSize(
    const Size(1050, 600),
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
