import 'package:dartboy/emulator/debugger.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartboy/emulator/audio/apu.dart' show getQueuedAudioSize;
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/gamepad_map.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gamepads/gamepads.dart';

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
  Future<void> loadROM(Uint8List data) async {
    if (state != EmulatorState.waiting) {
      cpu?.reset();
      print("Emulator was reset to load ROM.");
      return Future.value();
    }

    Cartridge cartridge = Cartridge();
    cartridge.load(data);

    cpu = CPU(cartridge);

    state = EmulatorState.ready;

    await printCartridgeInfo();

    // Skip gamepad initialization on Android due to plugin issues
    if (!Platform.isAndroid) {
      print("Available Controllers:");
      try {
        final gamepads = Gamepads.list();
        gamepads.then((List<GamepadController> controllers) {
          for (GamepadController controller in controllers) {
            print("[${controller.id}] ${controller.name}");
          }
        });
      } catch (e) {
        print("Error listing gamepads: $e");
      }

      try {
        Gamepads.events.listen(
          (GamepadEvent event) => onGamepadEvent(event),
        );
      } catch (e) {
        print("Error setting up gamepad event listener: $e");
      }
    } else {
      print("Gamepad support disabled on Android");
    }

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
  Future<void> printCartridgeInfo() async {
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

    // Note: Window title management removed for cross-platform compatibility
    // Title would be: 'Dart Boy: ${cpu?.cartridge.name}'

    await cpu?.apu.init();
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

  /// Run the emulation paced to native Game Boy speed.
  ///
  /// The Game Boy CPU runs at 4194304 Hz; one frame is exactly 70224 cycles,
  /// which gives a frame rate of ~59.7275 Hz (≈16742 µs/frame). Pacing uses
  /// the audio queue depth as the primary sync source when audio is enabled —
  /// SDL drains samples at 44100 Hz, so keeping the queue at a steady level
  /// keeps the emulator locked to real time. When audio is disabled, we fall
  /// back to wall-clock pacing using the exact 16742 µs frame budget.
  void run() async {
    if (state != EmulatorState.ready) {
      print("Emulator not ready, cannot run.");
      return;
    }

    await cpu?.initialize();

    state = EmulatorState.running;

    // Native Game Boy frame timing: one frame = 70224 T-cycles, and at
    // 4194304 Hz that lands at 16742 µs/frame (≈59.7275 Hz).
    const int frameTimeMicros = 16742;

    // Audio pacing target: keep around ~3 frames of samples queued. SDL drops
    // additional samples at MAX_QUEUED_AUDIO (88200 bytes ≈ 0.5 s at 44.1 kHz
    // stereo 16-bit), so this leaves plenty of slack while staying low-latency.
    // 1 frame at 44.1 kHz stereo 16-bit ≈ 2952 bytes; aim for ~3× that.
    const int audioTargetBytes = 9000;

    cycles = 0;
    int frameCounter = 0;
    int totalCyclesThisSecond = 0;

    Stopwatch perfStopwatch = Stopwatch()..start();
    Stopwatch wallClock = Stopwatch()..start();
    int nextFrameDeadlineMicros = frameTimeMicros;

    loop() async {
      while (state == EmulatorState.running) {
        try {
          // The CPU can be reassigned/cleared between frames when a ROM is
          // (re)loaded; bail out cleanly instead of crashing on null check.
          final activeCpu = cpu;
          if (activeCpu == null) {
            state = EmulatorState.ready;
            break;
          }

          // Run cycles until the PPU signals end-of-frame (LY → 144). One
          // iteration of this outer loop is exactly one Game Boy frame
          // (= cyclesPerFrame T-cycles).
          while (!activeCpu.ppu.frameReady) {
            int cyclesUsed = activeCpu.cycle();
            cycles += cyclesUsed;
            totalCyclesThisSecond += cyclesUsed;
          }
          activeCpu.flushPendingUpdates();
          activeCpu.ppu.resetFrameReady();

          frameCounter++;
          if (perfStopwatch.elapsedMilliseconds >= 1000) {
            double elapsedSeconds = perfStopwatch.elapsedMicroseconds / 1e6;
            speed = (totalCyclesThisSecond / elapsedSeconds).toInt();
            fps = (frameCounter / elapsedSeconds).round();
            perfStopwatch.reset();
            frameCounter = 0;
            totalCyclesThisSecond = 0;
          }

          // Pace to real time. Prefer audio-driven sync when audio is
          // initialized and reporting a queue size — SDL consumes samples at
          // exactly 44100 Hz, so backing off when the queue is full
          // automatically locks emulation to real time without drift.
          int audioQueued = -1;
          if (activeCpu.apu.isInitialized && !kIsWeb) {
            try {
              audioQueued = getQueuedAudioSize();
            } catch (_) {
              audioQueued = -1;
            }
          }

          if (audioQueued > audioTargetBytes) {
            // Audio is well-buffered; sleep proportional to overshoot. Each
            // byte represents 1/176400 s = ~5.67 µs of audio.
            int overshootBytes = audioQueued - audioTargetBytes;
            int sleepMicros = overshootBytes * 1000000 ~/ 176400;
            // Cap the sleep so the GUI still responds and we don't oversleep
            // past the next frame deadline by more than one frame.
            if (sleepMicros > frameTimeMicros * 2) {
              sleepMicros = frameTimeMicros * 2;
            }
            if (sleepMicros >= 1000) {
              await Future.delayed(Duration(microseconds: sleepMicros));
            }
            // Resync the wall-clock deadline to "now" so audio-paced and
            // wall-clock-paced runs don't drift apart from each other.
            nextFrameDeadlineMicros =
                wallClock.elapsedMicroseconds + frameTimeMicros;
          } else {
            // No audio (or audio queue underrunning) — pace by wall clock.
            int now = wallClock.elapsedMicroseconds;
            int sleepMicros = nextFrameDeadlineMicros - now;
            if (sleepMicros >= 1000) {
              await Future.delayed(Duration(microseconds: sleepMicros));
            } else if (sleepMicros < -frameTimeMicros * 4) {
              // Fell badly behind — drop the catch-up debt rather than
              // running flat-out (which would just sustain the lag).
              nextFrameDeadlineMicros = now + frameTimeMicros;
              continue;
            }
            nextFrameDeadlineMicros += frameTimeMicros;
          }
        } catch (e, s) {
          Debugger().getLogs().forEach((log) => print(log));
          print(e);
          print(s);
          state = EmulatorState.ready;
          rethrow;
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
