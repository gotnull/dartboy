import 'dart:async';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/gui/button.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:dartboy/gui/popup_sub_menu.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({
    required this.title,
    super.key,
  });

  final String title;

  /// Emulator instance
  static Emulator emulator = Emulator();

  static LCDState lcdState = LCDState();

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

  void _onRomSelected(String? romPath) {
    if (romPath != null) {
      print('ROM selected: $romPath');
      _debugFile(romPath); // You can load the ROM here
    }
  }

  Future<void> _debugFile(String? value) async {
    try {
      // Reset the emulator first
      _resetEmulator();

      // Try loading the asset
      ByteData romData = await rootBundle.load(value ?? "cpu_instrs.gb");

      // If successful, proceed with loading ROM
      Uint8List romBytes = romData.buffer.asUint8List();

      if (!mounted) return;

      MainScreen.emulator.loadROM(romBytes);
      MainScreen.emulator.state = EmulatorState.ready;

      _startEmulator();

      setState(() {}); // Trigger UI rebuild after loading ROM
    } catch (e) {
      // Handle the case where the file does not exist
      print('Error: Could not load file. Make sure the asset exists.');
      Modal.alert(
        context,
        'Error',
        'Error: Could not load the "cpu_instrs.gb" ROM. Make sure the ROM exists in the "assets/roms" folder.',
        onCancel: () => {},
      );
    }
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
      // Modal.alert(
      //   context,
      //   'Error',
      //   'No valid ROM file selected.',
      //   onCancel: () => {},
      // );
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
    MainScreen.emulator.cpu?.apu.stopAudio(); // Stop audio recording
    _stopHudUpdateTimer(); // Stop the HUD refresh timer when paused
    setState(() {}); // Trigger UI rebuild after pausing
  }

  void _resetEmulator() {
    MainScreen.emulator.cpu?.apu.stopAudio(); // Stop audio recording
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
      body: SizedBox(
        child: Row(
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
                    Text(
                      'HUD',
                      style: proggyTextStyle(),
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
                            MyRomMenu(onRomSelected: _onRomSelected),
                            // dropdownButton(
                            //   cpu: cpu,
                            //   romMap: MainScreen.romMap,
                            //   onChanged: (String? value) {
                            //     _debugFile(value);
                            //   },
                            // ),
                            customButton(
                              cpu: cpu,
                              label: 'Load',
                              onPressed: () {
                                _loadFile();
                              },
                            ),
                            customButton(
                              cpu: cpu,
                              label: 'Run',
                              onPressed: () {
                                _runEmulator();
                              },
                            ),
                            customButton(
                              cpu: cpu,
                              label: 'Pause',
                              onPressed: () {
                                _pauseEmulator();
                              },
                            ),
                            customButton(
                              cpu: cpu,
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
                              style: proggyTextStyle(),
                            ),
                            Text(
                              'speed: ${MainScreen.emulator.speed}Hz',
                              style: proggyTextStyle(),
                            ),
                            Text(
                              'FPS: ${MainScreen.emulator.fps.toStringAsFixed(2)}',
                              style: proggyTextStyle(),
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
                                                Text(
                                                  'PC ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  cpu.pc.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'A ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  registers.a.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'B ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  registers.b.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'D ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  registers.d.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'H ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  registers.h.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'Z ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.zeroFlagSet}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'H ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.halfCarryFlagSet}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'IME ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${cpu.interruptsEnabled}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'IF ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${cpu.interruptsEnabled}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
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
                                                Text(
                                                  'SP ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  cpu.sp.toRadixString(16),
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'F ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.f}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'C ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.c}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'E ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.e}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'L ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.l}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'N ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.subtractFlagSet}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'C ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.carryFlagSet}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  'IE ',
                                                  style: proggyTextStyle(),
                                                ),
                                                Text(
                                                  '${registers.carryFlagSet}',
                                                  style: proggyTextStyle(
                                                    color: Colors.green,
                                                  ),
                                                )
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
                              Text(
                                'No register data available',
                                style: proggyTextStyle(
                                  color: Colors.red,
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
      ),
    );
  }
}
