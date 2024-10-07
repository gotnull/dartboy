import 'package:flutter/material.dart';
import 'gui/main_screen.dart';

void main() {
  runApp(const DartBoy());
}

class DartBoy extends StatelessWidget {
  const DartBoy({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GBC',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(title: 'GBC', key: Key('gbc')),
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      showSemanticsDebugger: false,
      debugShowMaterialGrid: false,
    );
  }
}
