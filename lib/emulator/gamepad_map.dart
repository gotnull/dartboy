import 'dart:io';
import 'package:gamepads/gamepads.dart';

const _joystickAxisMaxValueLinux = 32767;

abstract class GamepadKey {
  const GamepadKey();

  bool matches(GamepadEvent event);
}

class GamepadAnalogAxis implements GamepadKey {
  final String linuxKeyName;
  final String macosKeyName;
  final String windowsKeyName;

  const GamepadAnalogAxis({
    required this.linuxKeyName,
    required this.macosKeyName,
    required this.windowsKeyName,
  });

  @override
  bool matches(GamepadEvent event) {
    final key = event.key;
    final isKey =
        key == linuxKeyName || key == macosKeyName || key == windowsKeyName;
    return isKey && event.type == KeyType.analog;
  }

  static double normalizedIntensity(GamepadEvent event) {
    final intensity = Platform.isMacOS
        ? event.value
        : (event.value / _joystickAxisMaxValueLinux).clamp(-1.0, 1.0);

    if (intensity.abs() < 0.2) {
      return 0;
    }
    return intensity;
  }
}

class GamepadButtonKey extends GamepadKey {
  final String linuxKeyName;
  final String macosKeyName;
  final String windowsKeyName;

  const GamepadButtonKey({
    required this.linuxKeyName,
    required this.macosKeyName,
    required this.windowsKeyName,
  });

  @override
  bool matches(GamepadEvent event) {
    final isKey = event.key == linuxKeyName ||
        event.key == macosKeyName ||
        event.key == windowsKeyName;
    return isKey && event.value == 1.0 && event.type == KeyType.button;
  }
}

class GamepadBumperKey extends GamepadKey {
  final String key;

  const GamepadBumperKey({required this.key});

  @override
  bool matches(GamepadEvent event) {
    return event.key == key && event.value == 9000.0 ||
        event.value == 27000.0 && event.type == KeyType.analog;
  }
}

const leftXAxis = GamepadAnalogAxis(
  linuxKeyName: '0',
  macosKeyName: 'l.joystick - xAxis',
  windowsKeyName: '???',
);

const leftYAxis = GamepadAnalogAxis(
  linuxKeyName: '1',
  macosKeyName: 'l.joystick - yAxis',
  windowsKeyName: '???',
);

const rightXAxis = GamepadAnalogAxis(
  linuxKeyName: '3',
  macosKeyName: 'r.joystick - xAxis',
  windowsKeyName: '???',
);

const rightYAxis = GamepadAnalogAxis(
  linuxKeyName: '4',
  macosKeyName: 'r.joystick - yAxis',
  windowsKeyName: '???',
);

const GamepadKey aButton = GamepadButtonKey(
  linuxKeyName: '0',
  macosKeyName: 'a.circle',
  windowsKeyName: "button-1",
);

const GamepadKey rShoulder = GamepadButtonKey(
  linuxKeyName: '0',
  macosKeyName: 'rb.rectangle.roundedbottom',
  windowsKeyName: "button-1",
);

const GamepadKey lShoulder = GamepadButtonKey(
  linuxKeyName: '0',
  macosKeyName: 'lb.rectangle.roundedbottom',
  windowsKeyName: "button-1",
);

const GamepadKey bButton = GamepadButtonKey(
  linuxKeyName: '1',
  macosKeyName: 'b.circle',
  windowsKeyName: "button-0",
);

const GamepadKey xButton = GamepadButtonKey(
  linuxKeyName: '2',
  macosKeyName: 'x.circle',
  windowsKeyName: "button-3",
);

const GamepadKey yButton = GamepadButtonKey(
  linuxKeyName: '2',
  macosKeyName: 'y.circle',
  windowsKeyName: "button-2",
);

const GamepadKey startButton = GamepadButtonKey(
  linuxKeyName: '7',
  macosKeyName: 'line.horizontal.3.circle',
  windowsKeyName: "button-7",
);

const GamepadKey selectButton = GamepadButtonKey(
  linuxKeyName: '6',
  macosKeyName: 'rectangle.fill.on.rectangle.fill.circle',
  windowsKeyName: "button-6",
);

const GamepadKey logoButton = GamepadButtonKey(
  linuxKeyName: '???',
  macosKeyName: 'logo.xbox',
  windowsKeyName: "???",
);

const GamepadKey dPadAxisX = GamepadButtonKey(
  linuxKeyName: '???',
  macosKeyName: 'dpad - xAxis',
  windowsKeyName: "???",
);

const GamepadKey dPadAxisY = GamepadButtonKey(
  linuxKeyName: '???',
  macosKeyName: 'dpad - yAxis',
  windowsKeyName: "???",
);

const GamepadKey l1Bumper = GamepadBumperKey(key: 'button-4');
const GamepadKey r1Bumper = GamepadBumperKey(key: 'button-5');
