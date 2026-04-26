import 'dart:async';
import 'dart:io';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:dartboy/utils/rom_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

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
  static String? currentRomName;

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  Timer? hudUpdateTimer;
  final Set<LogicalKeyboardKey> _pressedKeys = <LogicalKeyboardKey>{};
  List<RomInfo> availableRoms = [];
  bool isLoadingRoms = true;
  bool isRefreshingRoms = false;

  static const Color _bg = Color(0xFF07090C);
  static const Color _panel = Color(0xFF0D1117);
  static const Color _panelAlt = Color(0xFF121820);
  static const Color _border = Color(0xFF202834);
  static const Color _muted = Color(0xFF7D8590);
  static const Color _accent = Color(0xFF58A6FF);
  static const Color _green = Color(0xFF3DDC84);
  static const Color _amber = Color(0xFFFFB454);

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

  Future<void> _debugFile(String? value, [String? romName]) async {
    try {
      _resetEmulator();
      ByteData romData = await rootBundle.load(value ?? "cpu_instrs.gb");
      Uint8List romBytes = romData.buffer.asUint8List();

      if (!mounted) return;

      MainScreen.currentRomData = romBytes;
      MainScreen.currentRomName = romName;
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
    showFSheet(
      context: context,
      side: FLayout.btt,
      mainAxisMaxRatio: 0.78,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Game Library',
                  style: context.theme.typography.xl.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FBadge(child: Text('${availableRoms.length} games')),
                const SizedBox(width: 8),
                FButton.icon(
                  onPress: isRefreshingRoms
                      ? null
                      : () async {
                          setState(() => isRefreshingRoms = true);
                          await RomManager.refreshRomList();
                          await _loadAvailableRoms();
                          if (mounted) {
                            setState(() => isRefreshingRoms = false);
                          }
                        },
                  child: isRefreshingRoms
                      ? const FCircularProgress()
                      : const Icon(FIcons.refreshCw),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: (isLoadingRoms && availableRoms.isEmpty)
                  ? const Center(child: FCircularProgress())
                  : availableRoms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(FIcons.folderX, size: 44),
                              const SizedBox(height: 16),
                              Text(
                                'No ROMs found',
                                style: context.theme.typography.lg,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add ROM files to the assets/roms folder',
                                style: context.theme.typography.sm,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: availableRoms.length,
                          separatorBuilder: (context, index) =>
                              const FDivider(),
                          itemBuilder: (context, index) {
                            final rom = availableRoms[index];
                            return _GameTile(
                              title: rom.name,
                              subtitle: rom.platform,
                              isGBC: rom.platform.contains('Color'),
                              isTestRom: rom.isTestRom,
                              onTap: () {
                                Navigator.pop(context);
                                _debugFile(rom.path, rom.name);
                              },
                            );
                          },
                        ),
            ),
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

      // Extract ROM name from cartridge data
      try {
        final cartridge = Cartridge();
        cartridge.load(result.files.single.bytes!);
        String cartridgeName =
            cartridge.name.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
        if (cartridgeName.isEmpty) {
          // Use filename as fallback
          String fileName = result.files.single.name;
          cartridgeName = fileName.replaceAll(RegExp(r'\.(gb|gbc)$'), '');
        }
        MainScreen.currentRomName = cartridgeName;
      } catch (e) {
        // Fallback to filename if cartridge loading fails
        MainScreen.currentRomName =
            result.files.single.name.replaceAll(RegExp(r'\.(gb|gbc)$'), '');
      }

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
      child: FScaffold(
        childPad: false,
        child: ColoredBox(
          color: _bg,
          child: SafeArea(
            child: _isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;

    return isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout();
  }

  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Left Controls Panel
        SizedBox(
          width: 160,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLargeDPad(),
              const SizedBox(height: 32),
              _buildLargeSystemButtons(),
            ],
          ),
        ),

        // Center Game Area
        Expanded(
          child: Column(
            children: [
              // Minimal top bar
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(
                      FIcons.gamepad2,
                      color: Color(0xFF007AFF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        MainScreen.currentRomName ?? 'DartBoy',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${MainScreen.emulator.fps.toStringAsFixed(0)} FPS',
                      style: const TextStyle(
                        color: Color(0xFF007AFF),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Large Game Screen
              Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF2C2C2E),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                      BoxShadow(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.3),
                        blurRadius: 40,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: const AspectRatio(
                      aspectRatio: 160 / 144,
                      child: LCDWidget(key: Key("lcd")),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Controls Panel
        SizedBox(
          width: 160,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLargeActionButtons(),
              const SizedBox(height: 32),
              _buildLargeControlButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Minimal Header
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  FIcons.gamepad2,
                  color: Color(0xFF007AFF),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    MainScreen.currentRomName ?? 'DartBoy',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildQuickActions(),
              ],
            ),
          ),

          // Game Screen - Fixed height to prevent overflow
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildGameScreen(),
          ),

          const SizedBox(height: 16),

          // Virtual Controls
          _buildVirtualControls(),

          const SizedBox(height: 16),

          // Simple Control Panel
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSimpleControlButton(
                  icon: MainScreen.emulator.state == EmulatorState.running
                      ? FIcons.pause
                      : FIcons.play,
                  label: MainScreen.emulator.state == EmulatorState.running
                      ? 'Pause'
                      : 'Play',
                  onPressed: MainScreen.emulator.state == EmulatorState.running
                      ? _pauseEmulator
                      : _runOrStartEmulator,
                  color: MainScreen.emulator.state == EmulatorState.running
                      ? const Color(0xFFFF9500)
                      : const Color(0xFF34C759),
                ),
                _buildSimpleControlButton(
                  icon: FIcons.rotateCcw,
                  label: 'Reset',
                  onPressed: _resetEmulator,
                  color: const Color(0xFF8E8E93),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _buildDesktopToolbar(),
        Expanded(
          child: Row(
            children: [
              _buildRomRail(),
              const VerticalDivider(width: 1, thickness: 1, color: _border),
              Expanded(child: _buildEmulatorWorkspace()),
              const VerticalDivider(width: 1, thickness: 1, color: _border),
              _buildInspectorRail(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopToolbar() {
    final running = MainScreen.emulator.state == EmulatorState.running;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 24, color: _accent),
          const SizedBox(width: 12),
          const Icon(FIcons.gamepad2, size: 16, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'DartBoy',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFF0F6FC),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildStatePill(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildToolbarButton(
                    icon: FIcons.folderOpen,
                    label: 'Open ROM',
                    onPressed: _loadFile,
                  ),
                  const SizedBox(width: 8),
                  _buildToolbarButton(
                    icon: FIcons.library,
                    label: 'Library',
                    onPressed: (isLoadingRoms || isRefreshingRoms)
                        ? null
                        : _showRomSelection,
                  ),
                  const SizedBox(width: 12),
                  _buildToolbarButton(
                    icon: running ? FIcons.pause : FIcons.play,
                    label: running ? 'Pause' : 'Run',
                    isPrimary: true,
                    onPressed: running ? _pauseEmulator : _runOrStartEmulator,
                  ),
                  const SizedBox(width: 8),
                  _buildToolbarButton(
                    icon: FIcons.rotateCcw,
                    label: 'Reset',
                    onPressed: _resetEmulator,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    final enabled = onPressed != null;
    final color = isPrimary ? _green : const Color(0xFFD0D7DE);
    final borderColor = isPrimary
        ? _green.withValues(alpha: 0.45)
        : _border.withValues(alpha: enabled ? 1 : 0.5);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: isPrimary
                ? _green.withValues(alpha: 0.10)
                : const Color(0xFF0A0D12),
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatePill() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.08),
        border: Border.all(color: _getStatusColor().withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          MainScreen.emulator.state.name.toUpperCase(),
          style: TextStyle(
            color: _getStatusColor(),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildRomRail() {
    final roms = availableRoms.take(10).toList();

    return Container(
      width: 248,
      color: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRailHeader(
            title: 'Library',
            trailing: isRefreshingRoms
                ? const FCircularProgress()
                : _IconChromeButton(
                    icon: FIcons.refreshCw,
                    onPressed: () async {
                      setState(() => isRefreshingRoms = true);
                      await RomManager.refreshRomList();
                      await _loadAvailableRoms();
                      if (mounted) {
                        setState(() => isRefreshingRoms = false);
                      }
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              '${availableRoms.length} available ROMs',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: isLoadingRoms
                ? const Center(child: FCircularProgress())
                : roms.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No ROMs found',
                            style: TextStyle(color: _muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: roms.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final rom = roms[index];
                          final selected =
                              rom.name == MainScreen.currentRomName;
                          return _LibraryRow(
                            rom: rom,
                            selected: selected,
                            onTap: () => _debugFile(rom.path, rom.name),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: _TextChromeButton(
                onPress: (isLoadingRoms || isRefreshingRoms)
                    ? null
                    : _showRomSelection,
                icon: FIcons.library,
                label: 'Browse all',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRailHeader({required String title, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.sm.copyWith(
                color: _muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildEmulatorWorkspace() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: _bg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGameTitleBar(),
                const SizedBox(height: 14),
                Expanded(child: _buildViewport()),
              ],
            ),
          ),
        ),
        _buildDesktopStatusBar(),
      ],
    );
  }

  Widget _buildGameTitleBar() {
    return Row(
      children: [
        Expanded(
          child: Text(
            MainScreen.currentRomName ?? 'No cartridge loaded',
            overflow: TextOverflow.ellipsis,
            style: context.theme.typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
        Text(
          '${MainScreen.emulator.fps.toStringAsFixed(1)} FPS',
          style: const TextStyle(
            color: _accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        var width = maxWidth;
        var height = width * 144 / 160;

        if (height > maxHeight) {
          height = maxHeight;
          width = height * 160 / 144;
        }

        return Center(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: _accent.withValues(alpha: 0.04),
                  blurRadius: 60,
                ),
              ],
            ),
            child: const ClipRect(
              child: LCDWidget(key: Key("lcd")),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopStatusBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusSegment('State', MainScreen.emulator.state.name),
                  _buildStatusSegment('CPU', '${MainScreen.emulator.speed} Hz'),
                  _buildStatusSegment(
                      'Cycles', _formatNumber(MainScreen.emulator.cycles)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _getStatusText(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSegment(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE6EDF3),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorRail() {
    return Container(
      width: 300,
      color: _panel,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          _buildInspectorSection(
            title: 'Emulation',
            children: [
              _buildMetricRow('Frame rate',
                  '${MainScreen.emulator.fps.toStringAsFixed(1)} FPS'),
              _buildMetricRow('CPU speed', '${MainScreen.emulator.speed} Hz'),
              _buildMetricRow(
                  'Cycles', _formatNumber(MainScreen.emulator.cycles)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInspectorSection(
            title: 'System',
            action: _buildToggleButton(
              'Scanlines',
              MainScreen.scanlineEnabled,
              _toggleScanlines,
            ),
            children: [
              _buildMetricRow('ROM', MainScreen.currentRomName ?? 'None'),
              _buildMetricRow(
                  'State', MainScreen.emulator.state.name.toUpperCase()),
              _buildMetricRow('Platform', _getPlatformName()),
              _buildMetricRow('Version', '1.0.0'),
            ],
          ),
          const SizedBox(height: 12),
          _buildInspectorSection(
            title: 'Input Map',
            children: [
              _buildMetricRow('D-pad', 'Arrow keys'),
              _buildMetricRow('A / B', 'Z / X'),
              _buildMetricRow('Start', 'Enter'),
              _buildMetricRow('Select', 'Backspace'),
            ],
          ),
          const SizedBox(height: 12),
          _buildInspectorSection(
            title: 'Debug',
            action: _buildToggleButton(
              MainScreen.debugEnabled ? 'Hide' : 'Show',
              MainScreen.debugEnabled,
              _toggleDebug,
            ),
            children: MainScreen.debugEnabled ? _buildDebugRows() : const [],
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorSection({
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D12),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.sm.copyWith(
                    color: const Color(0xFFE6EDF3),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 9),
            ...children,
          ],
        ],
      ),
    );
  }

  List<Widget> _buildDebugRows() {
    final cpu = MainScreen.emulator.cpu;
    if (cpu == null) {
      return [_buildMetricRow('Status', 'CPU not loaded')];
    }

    return [
      _buildMetricRow(
          'PC', '0x${cpu.pc.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow(
          'SP', '0x${cpu.sp.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow('AF',
          '0x${cpu.registers.getRegisterPair(3).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow('BC',
          '0x${cpu.registers.getRegisterPair(0).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow('DE',
          '0x${cpu.registers.getRegisterPair(1).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow('HL',
          '0x${cpu.registers.getRegisterPair(2).toRadixString(16).toUpperCase().padLeft(4, '0')}'),
      _buildMetricRow('IME', cpu.interruptsEnabled ? 'Enabled' : 'Disabled'),
      _buildMetricRow('Halt', cpu.halted ? 'Yes' : 'No'),
    ];
  }

  Widget _buildQuickActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IOSButton(
          icon: FIcons.folderOpen,
          onPressed: _loadFile,
        ),
        const SizedBox(width: 8),
        _IOSButton(
          icon: FIcons.library,
          onPressed:
              (isLoadingRoms || isRefreshingRoms) ? null : _showRomSelection,
          isLoading: isLoadingRoms || isRefreshingRoms,
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

  Widget _buildToggleButton(String label, bool isEnabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: isEnabled
              ? _accent.withValues(alpha: 0.12)
              : const Color(0xFF161B22),
          border: Border.all(
            color: isEnabled ? _accent.withValues(alpha: 0.55) : _border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isEnabled ? _accent : _muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
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
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD0D7DE),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: _accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
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
        if (MainScreen.currentRomName != null) {
          return MainScreen.wasPaused
              ? 'Paused: ${MainScreen.currentRomName}'
              : 'Loaded: ${MainScreen.currentRomName}';
        } else {
          return MainScreen.wasPaused ? 'ROM paused' : 'ROM loaded';
        }
      case EmulatorState.running:
        if (MainScreen.currentRomName != null) {
          return 'Playing: ${MainScreen.currentRomName}';
        } else {
          return 'Running at ${MainScreen.emulator.fps.toStringAsFixed(1)} FPS';
        }
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

  Widget _buildLargeDPad() {
    return SizedBox(
      width: 120,
      height: 120,
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
            left: 35,
            child: _buildLargeDPadButton('▲', Gamepad.up),
          ),
          // Left
          Positioned(
            left: 0,
            top: 35,
            child: _buildLargeDPadButton('◄', Gamepad.left),
          ),
          // Right
          Positioned(
            right: 0,
            top: 35,
            child: _buildLargeDPadButton('►', Gamepad.right),
          ),
          // Down
          Positioned(
            bottom: 0,
            left: 35,
            child: _buildLargeDPadButton('▼', Gamepad.down),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeDPadButton(String label, int button) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeSystemButtons() {
    return Column(
      children: [
        _buildLargeSystemButton('SELECT', Gamepad.select),
        const SizedBox(height: 12),
        _buildLargeSystemButton('START', Gamepad.start),
      ],
    );
  }

  Widget _buildLargeSystemButton(String label, int button) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLargeActionButton('B', Gamepad.B, const Color(0xFF8E8E93)),
        const SizedBox(width: 20),
        _buildLargeActionButton('A', Gamepad.A, const Color(0xFF007AFF)),
      ],
    );
  }

  Widget _buildLargeActionButton(String label, int button, Color color) {
    return GestureDetector(
      onTapDown: (_) => _handleVirtualButton(button, true),
      onTapUp: (_) => _handleVirtualButton(button, false),
      onTapCancel: () => _handleVirtualButton(button, false),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLargeControlButtons() {
    return Column(
      children: [
        _buildLargeControlButton(
          icon: MainScreen.emulator.state == EmulatorState.running
              ? FIcons.pause
              : FIcons.play,
          label: MainScreen.emulator.state == EmulatorState.running
              ? 'PAUSE'
              : 'PLAY',
          onPressed: MainScreen.emulator.state == EmulatorState.running
              ? _pauseEmulator
              : _runOrStartEmulator,
          color: MainScreen.emulator.state == EmulatorState.running
              ? const Color(0xFFFF9500)
              : const Color(0xFF34C759),
        ),
        const SizedBox(height: 12),
        _buildLargeControlButton(
          icon: FIcons.rotateCcw,
          label: 'RESET',
          onPressed: _resetEmulator,
          color: const Color(0xFF8E8E93),
        ),
      ],
    );
  }

  Widget _buildLargeControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleControlButton({
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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
  final VoidCallback? onPressed;
  final bool isLoading;

  const _IOSButton({
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FButton.icon(
      onPress: onPressed,
      child: isLoading ? const FCircularProgress() : Icon(icon),
    );
  }
}

class _IconChromeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _IconChromeButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D12),
            border: Border.all(color: MainScreenState._border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: MainScreenState._muted,
          ),
        ),
      ),
    );
  }
}

class _TextChromeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPress;

  const _TextChromeButton({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPress != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: onPress,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0D12),
            border: Border.all(color: MainScreenState._border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: const Color(0xFFD0D7DE)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD0D7DE),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final RomInfo rom;
  final bool selected;
  final VoidCallback onTap;

  const _LibraryRow({
    required this.rom,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = rom.isTestRom
        ? MainScreenState._amber
        : (rom.platform.contains('Color')
            ? MainScreenState._accent
            : MainScreenState._muted);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? MainScreenState._panelAlt : const Color(0xFF0A0D12),
          border: Border.all(
            color: selected ? MainScreenState._accent : MainScreenState._border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 26,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    rom.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rom.platform,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MainScreenState._muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                    : (isGBC
                        ? const Color(0xFF007AFF)
                        : const Color(0xFF8E8E93)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isTestRom ? FIcons.bug : FIcons.gamepad2,
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
              FIcons.chevronRight,
              color: Color(0xFF8E8E93),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
