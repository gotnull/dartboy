import 'dart:async';
import 'dart:io';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:dartboy/utils/rom_manager.dart';
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

  static bool scanlineEnabled = false;
  static bool debugEnabled = false;
  static bool wasPaused = false;
  static Uint8List? currentRomData;

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  Timer? hudUpdateTimer;
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  List<RomInfo> availableRoms = [];
  bool isLoadingRoms = true;
  bool isRefreshingRoms = false;

  @override
  void initState() {
    super.initState();
    _startHudUpdateTimer();
    _loadAvailableRoms();
  }

  Future<void> _loadAvailableRoms() async {
    try {
      final roms = await RomManager.getAvailableRoms();
      if (mounted) {
        setState(() {
          availableRoms = roms;
          isLoadingRoms = false;
        });
      }
    } catch (e) {
      print('Error loading ROMs: $e');
      if (mounted) {
        setState(() {
          isLoadingRoms = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stopHudUpdateTimer();
    super.dispose();
  }

  void _startHudUpdateTimer() {
    hudUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopHudUpdateTimer() {
    hudUpdateTimer?.cancel();
  }

  Future<void> _debugFile(String? value) async {
    try {
      _resetEmulator();
      ByteData romData = await rootBundle.load(value ?? "cpu_instrs.gb");
      Uint8List romBytes = romData.buffer.asUint8List();

      if (!mounted) return;

      MainScreen.currentRomData = romBytes;
      MainScreen.emulator.loadROM(romBytes);
      MainScreen.emulator.state = EmulatorState.ready;
      _startEmulator();
      setState(() {});
    } catch (e) {
      print('Error: Could not load file. Make sure the asset exists.');
      Modal.alert(
        context,
        'Error',
        'Could not load the ROM. Make sure the ROM exists in the assets folder.',
        onCancel: () => {},
      );
    }
  }


  void _showRomSelection() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF8E8E93).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Game Library',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${availableRoms.length} games',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Refresh button
                  GestureDetector(
                    onTap: () async {
                      setState(() => isRefreshingRoms = true);
                      await RomManager.refreshRomList();
                      await _loadAvailableRoms();
                      if (mounted) {
                        setState(() => isRefreshingRoms = false);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: isRefreshingRoms
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF007AFF),
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              color: Color(0xFF007AFF),
                              size: 16,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Game List
            Expanded(
              child: (isLoadingRoms && availableRoms.isEmpty)
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF007AFF),
                      ),
                    )
                  : availableRoms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.videogame_asset_off_rounded,
                                size: 64,
                                color: const Color(0xFF8E8E93).withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No ROMs found',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFF8E8E93),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add ROM files to the assets/roms folder',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: availableRoms.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final rom = availableRoms[index];
                            return _GameTile(
                              title: rom.name,
                              subtitle: rom.platform,
                              isGBC: rom.platform.contains('Color'),
                              isTestRom: rom.isTestRom,
                              onTap: () {
                                Navigator.pop(context);
                                _debugFile(rom.path);
                              },
                            );
                          },
                        ),
            ),

            // Bottom padding
            SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose ROM',
      withData: true,
    );

    if (!mounted) return;

    if (result != null && result.files.single.bytes != null) {
      _resetEmulator();
      MainScreen.currentRomData = result.files.single.bytes!;
      MainScreen.emulator.loadROM(result.files.single.bytes!);
      MainScreen.emulator.state = EmulatorState.ready;
      _startEmulator();
      setState(() {});
    }
  }

  void _startEmulator() {
    MainScreen.emulator.run();
    // Initialize audio if needed
    final cpu = MainScreen.emulator.cpu;
    if (cpu != null && !cpu.apu.isInitialized) {
      cpu.apu.init();
    }
    _startHudUpdateTimer();
    setState(() {});
  }

  void _runEmulator() {
    if (MainScreen.emulator.state != EmulatorState.ready) {
      Modal.alert(
        context,
        'Not Ready',
        'Please load a ROM first.',
        onCancel: () {},
      );
      return;
    }
    MainScreen.emulator.run();
    MainScreen.wasPaused = false;
    // Initialize audio if needed
    final cpu = MainScreen.emulator.cpu;
    if (cpu != null && !cpu.apu.isInitialized) {
      cpu.apu.init();
    }
    _startHudUpdateTimer();
    setState(() {});
  }

  void _pauseEmulator() {
    if (MainScreen.emulator.state != EmulatorState.running) {
      return;
    }
    MainScreen.emulator.pause();
    MainScreen.wasPaused = true;
    // Don't stop audio completely when pausing - let the emulator handle it
    _stopHudUpdateTimer();
    setState(() {});
  }

  void _resetEmulator() {
    MainScreen.emulator.cpu?.apu.stopAudio();
    MainScreen.emulator.reset();
    MainScreen.wasPaused = false;
    _stopHudUpdateTimer();
    setState(() {});
  }

  void _handleKeyEvent(KeyEvent event) {
    final cpu = MainScreen.emulator.cpu;
    if (cpu == null) return;

    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      _pressedKeys.add(key);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
    }

    _updateGameBoyButtons(cpu);
  }

  void _updateGameBoyButtons(CPU cpu) {
    cpu.buttons[Gamepad.up] = _pressedKeys.contains(LogicalKeyboardKey.arrowUp);
    cpu.buttons[Gamepad.down] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowDown);
    cpu.buttons[Gamepad.left] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowLeft);
    cpu.buttons[Gamepad.right] =
        _pressedKeys.contains(LogicalKeyboardKey.arrowRight);
    cpu.buttons[Gamepad.A] = _pressedKeys.contains(LogicalKeyboardKey.keyZ);
    cpu.buttons[Gamepad.B] = _pressedKeys.contains(LogicalKeyboardKey.keyX);
    cpu.buttons[Gamepad.start] =
        _pressedKeys.contains(LogicalKeyboardKey.enter);
    cpu.buttons[Gamepad.select] =
        _pressedKeys.contains(LogicalKeyboardKey.backspace);
  }

  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: SafeArea(
          child: _isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Header
        _buildHeader(),

        // Game Screen
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildGameScreen(),
          ),
        ),

        const SizedBox(height: 24),

        // Virtual Controls
        _buildVirtualControls(),

        const SizedBox(height: 24),

        // Control Panel
        _buildMobileControlPanel(),

        const SizedBox(height: 12),

        // Status
        _buildStatusBar(),

        // Debug info for mobile
        if (MainScreen.debugEnabled) ...[
          const SizedBox(height: 12),
          _buildMobileDebugInfo(),
        ],

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Panel - Game Screen
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                Expanded(child: _buildGameScreen()),
                const SizedBox(height: 24),
                _buildDesktopControlPanel(),
              ],
            ),
          ),
        ),

        // Right Panel - Info
        Container(
          width: 320,
          color: const Color(0xFF1C1C1E),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                _buildPerformanceCard(),
                const SizedBox(height: 24),
                _buildSystemCard(),
                const SizedBox(height: 24),
                _buildDebugCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.videogame_asset_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DartBoy',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  _getStatusText(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _getStatusColor(),
                      ),
                ),
              ],
            ),
          ),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IOSButton(
          icon: Icons.folder_rounded,
          onPressed: _loadFile,
        ),
        const SizedBox(width: 8),
        _IOSButton(
          icon: Icons.library_books_rounded,
          onPressed: _showRomSelection,
        ),
      ],
    );
  }

  Widget _buildGameScreen() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2C2C2E),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: const AspectRatio(
          aspectRatio: 160 / 144,
          child: LCDWidget(key: Key("lcd")),
        ),
      ),
    );
  }

  Widget _buildVirtualControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // D-Pad
          _buildDPad(),

          // Action Buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDPad() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        children: [
          // Center piece
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Up
          Positioned(
            top: 0,
            left: 50,
            child: _buildDPadButton('▲', Gamepad.up),
          ),
          // Left
          Positioned(
            left: 0,
            top: 50,
            child: _buildDPadButton('◄', Gamepad.left),
          ),
          // Right
          Positioned(
            right: 0,
            top: 50,
            child: _buildDPadButton('►', Gamepad.right),
          ),
          // Down
          Positioned(
            bottom: 0,
            left: 50,
            child: _buildDPadButton('▼', Gamepad.down),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            _buildActionButton('B', Gamepad.B, const Color(0xFF8E8E93)),
            const SizedBox(width: 20),
            _buildActionButton('A', Gamepad.A, const Color(0xFF007AFF)),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildSystemButton('SELECT', Gamepad.select),
            const SizedBox(width: 20),
            _buildSystemButton('START', Gamepad.start),
          ],
        ),
      ],
    );
  }

  Widget _buildDPadButton(String label, int button) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, int button, Color color) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemButton(String label, int button) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileControlPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: MainScreen.emulator.state == EmulatorState.running
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            label: MainScreen.emulator.state == EmulatorState.running
                ? 'Pause'
                : 'Run',
            onPressed: MainScreen.emulator.state == EmulatorState.running
                ? _pauseEmulator
                : _runOrStartEmulator,
            color: MainScreen.emulator.state == EmulatorState.running
                ? const Color(0xFFFF9500)
                : const Color(0xFF34C759),
          ),
          _buildControlButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onPressed: _resetEmulator,
            color: const Color(0xFF8E8E93),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopControlPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: MainScreen.emulator.state == EmulatorState.running
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            label: MainScreen.emulator.state == EmulatorState.running
                ? 'Pause'
                : 'Run',
            onPressed: MainScreen.emulator.state == EmulatorState.running
                ? _pauseEmulator
                : _runOrStartEmulator,
            color: MainScreen.emulator.state == EmulatorState.running
                ? const Color(0xFFFF9500)
                : const Color(0xFF34C759),
          ),
          _buildControlButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onPressed: _resetEmulator,
            color: const Color(0xFF8E8E93),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusItem(
                  'FPS', MainScreen.emulator.fps.toStringAsFixed(1)),
              _buildStatusItem('Speed', '${MainScreen.emulator.speed}Hz'),
              _buildStatusItem(
                  'Cycles', _formatNumber(MainScreen.emulator.cycles)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToggleButton(
                'Scanlines',
                MainScreen.scanlineEnabled,
                _toggleScanlines,
              ),
              _buildToggleButton(
                MainScreen.debugEnabled ? 'Hide Debug' : 'Show Debug',
                MainScreen.debugEnabled,
                _toggleDebug,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF007AFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildMetricRow('Frame Rate',
              '${MainScreen.emulator.fps.toStringAsFixed(1)} FPS'),
          _buildMetricRow('CPU Speed', '${MainScreen.emulator.speed} Hz'),
          _buildMetricRow('Cycles', _formatNumber(MainScreen.emulator.cycles)),
        ],
      ),
    );
  }

  Widget _buildSystemCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'System',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _buildToggleButton(
                'Scanlines',
                MainScreen.scanlineEnabled,
                _toggleScanlines,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetricRow(
              'State', MainScreen.emulator.state.name.toUpperCase()),
          _buildMetricRow('Platform', _getPlatformName()),
          _buildMetricRow('Version', '1.0.0'),
        ],
      ),
    );
  }

  Widget _buildDebugCard() {
    if (!MainScreen.debugEnabled) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Debug Info',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            _buildToggleButton(
              'Show',
              MainScreen.debugEnabled,
              _toggleDebug,
            ),
          ],
        ),
      );
    }

    final cpu = MainScreen.emulator.cpu;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Debug Info',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _buildToggleButton(
                'Hide',
                MainScreen.debugEnabled,
                _toggleDebug,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cpu != null) ...[
            _buildMetricRow('PC',
                '0x${cpu.pc.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow('SP',
                '0x${cpu.sp.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow('AF',
                '0x${cpu.registers.getRegisterPair(3).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow('BC',
                '0x${cpu.registers.getRegisterPair(0).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow('DE',
                '0x${cpu.registers.getRegisterPair(1).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow('HL',
                '0x${cpu.registers.getRegisterPair(2).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
            _buildMetricRow(
                'IME', cpu.interruptsEnabled ? 'Enabled' : 'Disabled'),
            _buildMetricRow('Halt', cpu.halted ? 'Yes' : 'No'),
          ] else ...[
            _buildMetricRow('Status', 'CPU Not Loaded'),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileDebugInfo() {
    final cpu = MainScreen.emulator.cpu;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug Info',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (cpu != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('PC',
                    '0x${cpu.pc.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                _buildStatusItem('SP',
                    '0x${cpu.sp.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                _buildStatusItem('AF',
                    '0x${cpu.registers.getRegisterPair(3).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('BC',
                    '0x${cpu.registers.getRegisterPair(0).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                _buildStatusItem('DE',
                    '0x${cpu.registers.getRegisterPair(1).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                _buildStatusItem('HL',
                    '0x${cpu.registers.getRegisterPair(2).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('IME', cpu.interruptsEnabled ? 'ON' : 'OFF'),
                _buildStatusItem('Halt', cpu.halted ? 'YES' : 'NO'),
                _buildStatusItem('', ''), // Empty for alignment
              ],
            ),
          ] else ...[
            Center(
              child: _buildStatusItem('Status', 'CPU Not Loaded'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isEnabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isEnabled ? const Color(0xFF007AFF) : const Color(0xFF3A3A3C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isEnabled ? Colors.white : const Color(0xFF8E8E93),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF007AFF),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText() {
    switch (MainScreen.emulator.state) {
      case EmulatorState.waiting:
        return 'Ready to load ROM';
      case EmulatorState.ready:
        return MainScreen.wasPaused ? 'ROM paused' : 'ROM loaded';
      case EmulatorState.running:
        return 'Running at ${MainScreen.emulator.fps.toStringAsFixed(1)} FPS';
    }
  }

  Color _getStatusColor() {
    switch (MainScreen.emulator.state) {
      case EmulatorState.running:
        return const Color(0xFF34C759);
      case EmulatorState.ready:
        return const Color(0xFFFF9500);
      case EmulatorState.waiting:
        return const Color(0xFF8E8E93);
    }
  }

  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  void _handleVirtualButton(int button, bool pressed) {
    final cpu = MainScreen.emulator.cpu;
    if (cpu != null) {
      cpu.buttons[button] = pressed;
    }
  }

  void _toggleScanlines() {
    setState(() {
      MainScreen.scanlineEnabled = !MainScreen.scanlineEnabled;
    });
  }

  void _toggleDebug() {
    setState(() {
      MainScreen.debugEnabled = !MainScreen.debugEnabled;
    });
  }

  void _runOrStartEmulator() {
    if (MainScreen.emulator.state == EmulatorState.ready) {
      _runEmulator();
    } else if (MainScreen.emulator.state == EmulatorState.waiting) {
      // Check if we have ROM data to reload
      if (MainScreen.currentRomData != null) {
        // Reload the ROM and start
        MainScreen.emulator.loadROM(MainScreen.currentRomData!);
        MainScreen.emulator.state = EmulatorState.ready;
        MainScreen.wasPaused = false;
        _runEmulator();
      } else {
        // Show alert that ROM needs to be loaded first
        Modal.alert(
          context,
          'Not Ready',
          'Please load a ROM first.',
          onCancel: () {},
        );
      }
    }
  }
}

class _IOSButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _IOSButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF007AFF),
          size: 16,
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isGBC;
  final bool isTestRom;
  final VoidCallback onTap;

  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.isGBC,
    required this.onTap,
    this.isTestRom = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isTestRom
                    ? const Color(0xFFFF9500)
                    : (isGBC ? const Color(0xFF007AFF) : const Color(0xFF8E8E93)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isTestRom ? Icons.bug_report_rounded : Icons.videogame_asset_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF8E8E93),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
