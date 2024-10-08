import 'dart:async';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({required Key key, required this.title}) : super(key: key);

  final String title;

  /// Emulator instance
  static Emulator emulator = Emulator();

  static LCDState lcdState = LCDState();

  static bool keyboardHandlerCreated = false;

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  Timer? hudUpdateTimer; // Timer to periodically update the HUD

  @override
  void initState() {
    super.initState();
    _startHudUpdateTimer();
  }

  @override
  void dispose() {
    _stopHudUpdateTimer();
    super.dispose();
  }

  /// Start a Timer to refresh the HUD every 500ms
  void _startHudUpdateTimer() {
    hudUpdateTimer = Timer.periodic(const Duration(milliseconds: 4), (timer) {
      if (mounted) {
        setState(() {
          // Trigger rebuild to update the HUD
        });
      }
    });
  }

  /// Stop the Timer when the emulator is paused or reset
  void _stopHudUpdateTimer() {
    hudUpdateTimer?.cancel();
  }

  Future<void> loadFile() async {
    // Load from assets
    ByteData romData = await rootBundle.load('assets/roms/cpu_instrs.gb');
    Uint8List romBytes = romData.buffer.asUint8List();

    if (!mounted) return;

    MainScreen.emulator.loadROM(romBytes);
    MainScreen.emulator.state = EmulatorState.ready;

    _runEmulator();

    setState(() {}); // Trigger UI rebuild after loading ROM
  }

  Future<void> pickFile() async {
    // Load from file picker
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose ROM',
      withData: true,
    );

    if (!mounted) return;

    if (result != null && result.files.single.bytes != null) {
      MainScreen.emulator.loadROM(result.files.single.bytes!);
      setState(() {}); // Trigger UI rebuild after loading ROM
    } else {
      Modal.alert(
        context,
        'Error',
        'No valid ROM file selected.',
        onCancel: () => {},
      );
    }
  }

  void _runEmulator() {
    if (MainScreen.emulator.state != EmulatorState.ready) {
      Modal.alert(
        context,
        'Error',
        'Not ready to run. Load ROM first.',
        onCancel: () {},
      );
      return;
    }
    MainScreen.emulator.run();
    _startHudUpdateTimer(); // Start the HUD refresh timer
    setState(() {}); // Trigger UI rebuild after running
  }

  void _pauseEmulator() {
    if (MainScreen.emulator.state != EmulatorState.running) {
      Modal.alert(
        context,
        'Error',
        "Not running, can't be paused.",
        onCancel: () {},
      );
      return;
    }
    MainScreen.emulator.pause();
    _stopHudUpdateTimer(); // Stop the HUD refresh timer when paused
    setState(() {}); // Trigger UI rebuild after pausing
  }

  void _resetEmulator() {
    MainScreen.emulator.reset();
    _stopHudUpdateTimer(); // Stop the HUD refresh timer when reset
    setState(() {}); // Trigger UI rebuild after reset
  }

  @override
  Widget build(BuildContext context) {
    final cpu = MainScreen.emulator.cpu;
    final registers = cpu?.registers;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Left side: LCD display
          Expanded(
            flex: 3,
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                ),
                child: const AspectRatio(
                  aspectRatio: 160 / 144, // Gameboy screen resolution
                  child: LCDWidget(key: Key('lcd')),
                ),
              ),
            ),
          ),

          // Right side: Debug controls and emulator info
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.white),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HUD',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  const Divider(color: Colors.grey),

                  // Emulator controls (Load, Pause, Run, Reset)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ElevatedButton(
                          onPressed: loadFile,
                          child: const Text('Debug'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ElevatedButton(
                          onPressed: pickFile,
                          child: const Text('Load'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ElevatedButton(
                          onPressed: _runEmulator,
                          child: const Text('Run'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ElevatedButton(
                          onPressed: _pauseEmulator,
                          child: const Text('Pause'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ElevatedButton(
                          onPressed: _resetEmulator,
                          child: const Text('Reset'),
                        ),
                      ),
                    ],
                  ),

                  const Divider(color: Colors.grey),

                  // Debug information (FPS, cycles, speed, registers)
                  Text(
                    'cycles: ${MainScreen.emulator.cycles}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'ProggyClean',
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'speed: ${MainScreen.emulator.speed}Hz',
                    style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'ProggyClean',
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'FPS: ${MainScreen.emulator.fps.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontFamily: 'ProggyClean',
                      fontSize: 18,
                    ),
                  ),

                  const Divider(color: Colors.grey),

                  // Registers (PC, A, B, D, H, SP, flags Z, N, H, C)
                  if (cpu != null && registers != null) ...[
                    Text(
                      'PC: ${cpu.pc.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'SP: ${cpu.sp.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'A: ${registers.a.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'B: ${registers.b.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'D: ${registers.d.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'H: ${registers.h.toRadixString(16)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    const Divider(color: Colors.grey),

                    // Flag values (Z, N, H, C)
                    Text(
                      'Zero Flag (Z): ${registers.zeroFlagSet}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Subtract Flag (N): ${registers.subtractFlagSet}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Half-Carry Flag (H): ${registers.halfCarryFlagSet}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Carry Flag (C): ${registers.carryFlagSet}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontFamily: 'ProggyClean',
                        fontSize: 18,
                      ),
                    ),
                  ] else
                    const Text(
                      'No register data available',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
