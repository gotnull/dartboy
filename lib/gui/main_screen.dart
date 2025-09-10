import 'dart:async';
import 'dart:io';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/gui/button.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:dartboy/gui/popup_sub_menu.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

  // Track keyboard key states to handle continuous input properly
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};

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

  /// Start a Timer to refresh the HUD at reasonable intervals
  void _startHudUpdateTimer() {
    hudUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
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

  void _handleKeyEvent(KeyEvent event) {
    final cpu = MainScreen.emulator.cpu;
    if (cpu == null) return;

    final key = event.logicalKey;

    // Update pressed key state
    if (event is KeyDownEvent) {
      _pressedKeys.add(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }

    // Update Game Boy button states based on currently pressed keys
    _updateGameBoyButtons(cpu);
  }

  void _updateGameBoyButtons(CPU cpu) {
    // Movement (D-Pad)
    cpu.buttons[Gamepad.up] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowUp) ||
            _pressedKeys.contains(LogicalKeyboardKey.keyW);
    cpu.buttons[Gamepad.down] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown) ||
            _pressedKeys.contains(LogicalKeyboardKey.keyS);
    cpu.buttons[Gamepad.left] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft) ||
            _pressedKeys.contains(LogicalKeyboardKey.keyA);
    cpu.buttons[Gamepad.right] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight) ||
            _pressedKeys.contains(LogicalKeyboardKey.keyD);

    // Action buttons
    cpu.buttons[Gamepad.A] = _pressedKeys.contains(LogicalKeyboardKey.keyX) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyJ);
    cpu.buttons[Gamepad.B] = _pressedKeys.contains(LogicalKeyboardKey.keyZ) ||
        _pressedKeys.contains(LogicalKeyboardKey.keyK);

    // System buttons
    cpu.buttons[Gamepad.start] =
        _pressedKeys.contains(LogicalKeyboardKey.enter) ||
            _pressedKeys.contains(LogicalKeyboardKey.space);
    cpu.buttons[Gamepad.select] =
        _pressedKeys.contains(LogicalKeyboardKey.shiftRight) ||
            _pressedKeys.contains(LogicalKeyboardKey.backspace);
  }

  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Widget build(BuildContext context) {
    final cpu = MainScreen.emulator.cpu;
    final registers = cpu?.registers;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _isMobile ? _buildMobileLayout(cpu, registers) : _buildDesktopLayout(cpu, registers),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(CPU? cpu, dynamic registers) {
    return Column(
      children: [
        // Game screen - takes most of the space
        Expanded(
          flex: 3,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(8),
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
        
        // Virtual Game Boy buttons
        _buildVirtualControls(),
        
        // Control buttons - compact row
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactButton('Load', () => _loadFile()),
              _buildCompactButton('Run', () => _runEmulator()),
              _buildCompactButton('Pause', () => _pauseEmulator()),
              _buildCompactButton('Reset', () => _resetEmulator()),
            ],
          ),
        ),
        
        // Status info - minimal
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'FPS: ${MainScreen.emulator.fps.toStringAsFixed(1)} | Speed: ${MainScreen.emulator.speed}Hz',
            style: const TextStyle(color: Colors.green, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(CPU? cpu, dynamic registers) {
    return Row(
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
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HUD', style: proggyTextStyle()),
                const Padding(padding: EdgeInsets.symmetric(vertical: 4.0)),
                
                // Emulator controls
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        MyRomMenu(onRomSelected: _onRomSelected),
                        customButton(cpu: cpu, label: 'Load', onPressed: () => _loadFile()),
                        customButton(cpu: cpu, label: 'Run', onPressed: () => _runEmulator()),
                        customButton(cpu: cpu, label: 'Pause', onPressed: () => _pauseEmulator()),
                        customButton(cpu: cpu, label: 'Reset', onPressed: () => _resetEmulator()),
                      ],
                    ),
                  ),
                ),
                
                const Padding(padding: EdgeInsets.symmetric(vertical: 4.0)),
                
                // Debug information
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('cycles: ${MainScreen.emulator.cycles}', style: proggyTextStyle()),
                          Text('speed: ${MainScreen.emulator.speed}Hz', style: proggyTextStyle()),
                          Text('FPS: ${MainScreen.emulator.fps.toStringAsFixed(2)}', style: proggyTextStyle()),
                          const Divider(color: Colors.grey),
                          if (cpu != null && registers != null) ...[
                            _buildRegisterInfo(cpu, registers),
                          ] else
                            Text('No register data available', style: proggyTextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVirtualControls() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // D-Pad
          Column(
            children: [
              _buildGameButton('↑', () => _handleVirtualButton(Gamepad.up, true), 
                             () => _handleVirtualButton(Gamepad.up, false)),
              Row(
                children: [
                  _buildGameButton('←', () => _handleVirtualButton(Gamepad.left, true),
                                 () => _handleVirtualButton(Gamepad.left, false)),
                  const SizedBox(width: 60),
                  _buildGameButton('→', () => _handleVirtualButton(Gamepad.right, true),
                                 () => _handleVirtualButton(Gamepad.right, false)),
                ],
              ),
              _buildGameButton('↓', () => _handleVirtualButton(Gamepad.down, true),
                             () => _handleVirtualButton(Gamepad.down, false)),
            ],
          ),
          
          // Action buttons
          Column(
            children: [
              const SizedBox(height: 40),
              Row(
                children: [
                  _buildGameButton('B', () => _handleVirtualButton(Gamepad.B, true),
                                 () => _handleVirtualButton(Gamepad.B, false)),
                  const SizedBox(width: 20),
                  _buildGameButton('A', () => _handleVirtualButton(Gamepad.A, true),
                                 () => _handleVirtualButton(Gamepad.A, false)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildGameButton('Select', () => _handleVirtualButton(Gamepad.select, true),
                                 () => _handleVirtualButton(Gamepad.select, false)),
                  const SizedBox(width: 10),
                  _buildGameButton('Start', () => _handleVirtualButton(Gamepad.start, true),
                                 () => _handleVirtualButton(Gamepad.start, false)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameButton(String label, VoidCallback onPressed, VoidCallback onReleased) {
    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => onReleased(),
      onTapCancel: onReleased,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          border: Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(60, 30),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildRegisterInfo(CPU cpu, dynamic registers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRegisterRow('PC', cpu.pc.toRadixString(16)),
              _buildRegisterRow('A', registers.a.toRadixString(16)),
              _buildRegisterRow('B', registers.b.toRadixString(16)),
              _buildRegisterRow('D', registers.d.toRadixString(16)),
              _buildRegisterRow('H', registers.h.toRadixString(16)),
              _buildRegisterRow('Z', '${registers.zeroFlagSet}'),
              _buildRegisterRow('H', '${registers.halfCarryFlagSet}'),
              _buildRegisterRow('IME', '${cpu.interruptsEnabled}'),
              _buildRegisterRow('IF', '${cpu.interruptsEnabled}'),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRegisterRow('SP', cpu.sp.toRadixString(16)),
              _buildRegisterRow('F', '${registers.f}'),
              _buildRegisterRow('C', '${registers.c}'),
              _buildRegisterRow('E', '${registers.e}'),
              _buildRegisterRow('L', '${registers.l}'),
              _buildRegisterRow('N', '${registers.subtractFlagSet}'),
              _buildRegisterRow('C', '${registers.carryFlagSet}'),
              _buildRegisterRow('IE', '${registers.carryFlagSet}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterRow(String label, String value) {
    return Row(
      children: [
        Text('$label ', style: proggyTextStyle()),
        Text(value, style: proggyTextStyle(color: Colors.green)),
      ],
    );
  }

  void _handleVirtualButton(int button, bool pressed) {
    final cpu = MainScreen.emulator.cpu;
    if (cpu != null) {
      cpu.buttons[button] = pressed;
    }
  }
}
