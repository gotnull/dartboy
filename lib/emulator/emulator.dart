import 'package:dartboy/emulator/debugger.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/gamepad_map.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:gamepads/gamepads.dart';
import 'package:window_manager/window_manager.dart';

/// Represents the state of the emulator.
///
/// If data is not loaded the emulator is in WAITING state, after loading data is get into READY state.
///
/// When the game starts running it goes to RUNNING state, on pause it returns to READY.
enum EmulatorState {
  waiting,
  ready,
  running,
}

/// Main emulator object used to directly interact with the system.
///
/// GUI communicates with this object, it is responsible for providing image, handling key input and user interaction.
class Emulator {
  /// State of the emulator, indicates if there is data loaded, and the emulation state.
  EmulatorState state = EmulatorState.waiting;

  /// CPU object
  CPU? cpu;

  int cycles = 0;
  int speed = 0;
  int fps = 0;

  /// Load a ROM from a file and create the HW components for the emulator.
  void loadROM(Uint8List data) {
    if (state != EmulatorState.waiting) {
      cpu?.reset();
      print("Emulator was reset to load ROM.");
      return;
    }

    Cartridge cartridge = Cartridge();
    cartridge.load(data);

    cpu = CPU(cartridge);

    state = EmulatorState.ready;

    printCartridgeInfo();

    print("Available Controllers:");
    final gamepads = Gamepads.list();
    gamepads.then((List<GamepadController> controllers) {
      for (GamepadController controller in controllers) {
        print("[${controller.id}] ${controller.name}");
      }
    });

    Gamepads.events.listen(
      (GamepadEvent event) => onGamepadEvent(event),
    );

    // Start recording audio when the ROM is loaded
    cpu?.apu.init();
  }

  void onGamepadEvent(GamepadEvent event) {
    _handleGamepadAxisInput(event);
    _handleGamepadMoveEvent(event);
  }

  void _handleGamepadAxisInput(GamepadEvent event) {
    double xAxis = event.key.contains("xAxis") ? event.value : 0.0;
    double yAxis = event.key.contains("yAxis") ? event.value : 0.0;

    // Reset Up and Down buttons before processing new input
    cpu?.buttons[Gamepad.up] = false;
    cpu?.buttons[Gamepad.down] = false;

    // Handle axis input for left, right, up, and down
    if (xAxis == -1.0) {
      cpu?.buttons[Gamepad.left] = true;
      // print("Left button set to true");
    } else if (xAxis == 1.0) {
      cpu?.buttons[Gamepad.right] = true;
      // print("Right button set to true");
    } else if (yAxis == 1.0) {
      cpu?.buttons[Gamepad.up] = true;
      // print("Up button set to true");
    } else if (yAxis == -1.0) {
      cpu?.buttons[Gamepad.down] = true;
      // print("Down button set to true");
    }

    // Reset Left and Right only if xAxis is neutral
    if (xAxis == 0.0 && event.key.contains("xAxis")) {
      cpu?.buttons[Gamepad.left] = false;
      cpu?.buttons[Gamepad.right] = false;
      // print("Left and Right buttons reset");
    }

    // Reset Up and Down if yAxis is neutral
    if (yAxis == 0.0) {
      cpu?.buttons[Gamepad.up] = false;
      cpu?.buttons[Gamepad.down] = false;
      // print("Up and Down buttons reset");
    }
  }

  void _handleGamepadMoveEvent(GamepadEvent event) {
    // Reset action buttons before processing new input
    cpu?.buttons[Gamepad.A] = false;
    cpu?.buttons[Gamepad.B] = false;
    cpu?.buttons[Gamepad.select] = false;
    cpu?.buttons[Gamepad.start] = false;

    // Check for each button event and update the state accordingly
    if (startButton.matches(event)) {
      cpu?.buttons[Gamepad.start] = true;
      // print("Start gamepad event");
    } else if (selectButton.matches(event)) {
      cpu?.buttons[Gamepad.select] = true;
      // print("Select gamepad event");
    } else if (aButton.matches(event)) {
      cpu?.buttons[Gamepad.B] = true; // B button
      // print("B gamepad event");
    } else if (bButton.matches(event)) {
      cpu?.buttons[Gamepad.A] = true; // A button
      // print("A gamepad event");
    }
  }

  /// Print some information about the ROM file loaded into the emulator.
  void printCartridgeInfo() {
    print("Cartridge info:");
    print("Title: ${cpu?.cartridge.name}");
    print("ROM Size: ${cpu?.cartridge.size}k");
    print("ROM Banks: ${cpu?.cartridge.romBanks}");
    print("RAM Size: ${cpu?.cartridge.getRamSize()}");
    print("Cartridge Type: ${cpu?.cartridge.type}");
    print("GB: ${cpu?.cartridge.gameboyType}");
    print("SGB: ${cpu?.cartridge.superGameboy}");
    print(
      "Manufacturer Code: ${cpu?.cartridge.cartManufacturerCode.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}",
    );

    windowManager.setTitle(
      'Dart Boy: ${cpu?.cartridge.name}',
    );

    cpu?.apu.init();
  }

  /// Reset the emulator, stop running the code and unload the cartridge
  void reset() {
    cpu?.reset();
    cpu = null;
    state = EmulatorState.waiting;
  }

  /// Do a single step in the cpu, set it to debug mode, step and then reset.
  void debugStep() {
    if (state != EmulatorState.ready) {
      print("Emulator not ready, cannot step.");
      return;
    }

    bool wasDebug = Configuration.debugInstructions;
    Configuration.debugInstructions = true;
    cpu?.cycle();
    Configuration.debugInstructions = wasDebug;
  }

  /// Run the emulation at full speed.
  void run() async {
    if (state != EmulatorState.ready) {
      print("Emulator not ready, cannot run.");
      return;
    }

    await cpu?.initialize();

    state = EmulatorState.running;

    int frequency = CPU.frequency;

    // FPS target
    fps = 60; // Standard for most emulators
    double periodFPS = 1e6 / fps; // Time per frame in microseconds

    // Track cycles
    cycles = 0;
    int frameCycles = frequency ~/ fps; // Cycles per frame for 60fps
    int frameCounter = 0;

    // Use a stopwatch to measure actual FPS
    Stopwatch stopwatch = Stopwatch()..start();
    Stopwatch frameStopwatch = Stopwatch()..start();

    loop() async {
      while (state == EmulatorState.running) {
        frameStopwatch.reset();
        try {
          // Execute CPU steps for one frame
          while (!cpu!.ppu.frameReady) {
            cpu!.cycle();
          }
          cpu!.ppu.resetFrameReady();

          // Calculate speed and FPS
          frameCounter++;
          if (stopwatch.elapsedMilliseconds >= 1000) {
            double elapsedSeconds = stopwatch.elapsedMicroseconds / 1e6;
            speed = (cycles / elapsedSeconds).toInt(); // CPU speed in Hz
            fps = (frameCounter / elapsedSeconds).round(); // Actual frames per second

            stopwatch.reset();
            frameCounter = 0;
            cycles = 0;
          }

          // Wait for the next frame
          int elapsedMicroseconds = frameStopwatch.elapsedMicroseconds;
          int delayMicroseconds = periodFPS.toInt() - elapsedMicroseconds;
          if (delayMicroseconds > 0) {
            await Future.delayed(Duration(microseconds: delayMicroseconds));
          }
        } catch (e, s) {
          Debugger().getLogs().forEach((log) => print(log));
          print(e);
          print(s);
          state = EmulatorState.ready;
          throw e;
        }
      }
    }

    loop();
  }

  /// Pause the emulation
  void pause() {
    if (state != EmulatorState.running) {
      print("Emulator not running cannot be paused");
      return;
    }

    state = EmulatorState.ready;
  }
}
