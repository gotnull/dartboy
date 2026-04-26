import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'gui/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DartBoy());
}

class DartBoy extends StatelessWidget {
  const DartBoy({super.key});

  @override
  Widget build(BuildContext context) {
    final foruiTheme = FThemes.zinc.dark.touch;

    return MaterialApp(
      title: 'DartBoy',
      theme: foruiTheme.toApproximateMaterialTheme(),
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      builder: (context, child) => FTheme(
        data: foruiTheme,
        child: child!,
      ),
      home: const MainScreen(title: 'DartBoy', key: Key("dartBoy")),
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      showSemanticsDebugger: false,
      debugShowMaterialGrid: false,
    );
  }
}
