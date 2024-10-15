import 'dart:async';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/gui/button.dart';
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

  Future<void> _debugFile() async {
    // Reset the emulator first
    _resetEmulator();

    // Load from assets
    ByteData romData = await rootBundle.load(
      // "assets/roms/blargg/cpu_instrs/cpu_instrs.gb",
      "assets/roms/tetris_world_dx.gbc",
    );

    Uint8List romBytes = romData.buffer.asUint8List();

    if (!mounted) return;

    MainScreen.emulator.loadROM(romBytes);
    MainScreen.emulator.state = EmulatorState.ready;

    _startEmulator();

    setState(() {}); // Trigger UI rebuild after loading ROM
  }

  Future<void> _loadFile() async {
    // Load from file picker
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose ROM',
      withData: true,
    );

    if (!mounted) return;

    if (result != null && result.files.single.bytes != null) {
      _resetEmulator();
      MainScreen.emulator.loadROM(result.files.single.bytes!);
    } else {
      Modal.alert(
        context,
        'Error',
        'No valid ROM file selected.',
        onCancel: () => {},
      );
    }
  }

  void _startEmulator() {
    MainScreen.emulator.run();
    _startHudUpdateTimer(); // Start the HUD refresh timer
    setState(() {}); // Trigger UI rebuild after loading ROM
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
                  child: LCDWidget(key: Key("lcd")),
                ),
              ),
            ),
          ),

          // Right side: Debug controls and emulator info
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(
                8.0,
              ), // Add padding inside the border
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                ), // Set border color and thickness
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HUD',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'ProggyClean',
                      fontSize: 18,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                  ),
                  // Emulator controls (Load, Pause, Run, Reset)
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      padding: const EdgeInsets.all(
                          8.0), // Add padding inside the border
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                        ), // Set border color and thickness
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          customButton(
                            label: 'Debug',
                            onPressed: () {
                              _debugFile();
                            },
                          ),
                          customButton(
                            label: 'Load',
                            onPressed: () {
                              _loadFile();
                            },
                          ),
                          customButton(
                            label: 'Run',
                            onPressed: () {
                              _runEmulator();
                            },
                          ),
                          customButton(
                            label: 'Pause',
                            onPressed: () {
                              _pauseEmulator();
                            },
                          ),
                          customButton(
                            label: 'Reset',
                            onPressed: () {
                              _resetEmulator();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                  ),
                  // Debug information (FPS, cycles, speed, registers)
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(
                        8.0,
                      ), // Add padding inside the border
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                        ), // Set border color and thickness
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'cycles: ${MainScreen.emulator.cycles}',
                            style: const TextStyle(
                              color: Color.fromARGB(255, 169, 169, 169),
                              fontFamily: 'ProggyClean',
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'speed: ${MainScreen.emulator.speed}Hz',
                            style: const TextStyle(
                              color: Color.fromARGB(255, 169, 169, 169),
                              fontFamily: 'ProggyClean',
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'FPS: ${MainScreen.emulator.fps.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color.fromARGB(255, 169, 169, 169),
                              fontFamily: 'ProggyClean',
                              fontSize: 18,
                            ),
                          ),
                          const Divider(color: Colors.grey),
                          if (cpu != null && registers != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'PC ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                cpu.pc.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'A ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                registers.a.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'B ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                registers.b.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'D ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                registers.d.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'H ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                registers.h.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'Z ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.zeroFlagSet}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'H ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.halfCarryFlagSet}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'IME ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${cpu.interruptsEnabled}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'IF ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${cpu.interruptsEnabled}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ColoredBox(
                                      color: Colors.black,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                'SP ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                cpu.sp.toRadixString(16),
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'F ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.f}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'C ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.c}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'E ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.e}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'L ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.l}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'N ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.subtractFlagSet}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'C ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.carryFlagSet}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                'IE ',
                                                style: TextStyle(
                                                  color: Color.fromARGB(
                                                      255, 169, 169, 169),
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                '${registers.carryFlagSet}',
                                                style: const TextStyle(
                                                  color: Colors.green,
                                                  fontFamily: 'ProggyClean',
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else
                            const Text(
                              'No register data available',
                              style: TextStyle(
                                color: Colors.red,
                                fontFamily: 'ProggyClean',
                                fontSize: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
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
