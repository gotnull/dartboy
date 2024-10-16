import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/gui/main_screen.dart';
import 'package:flutter/material.dart';

Widget customButton({
  required CPU? cpu,
  required String label,
  VoidCallback? onPressed, // The function to run when pressed
  Color backgroundColor = Colors.blue, // Optional: Background color
  Color textColor = Colors.white, // Optional: Text color
}) {
  bool isCartridgeLoaded = cpu != null && cpu.cartridge.data.isNotEmpty;

  return ElevatedButton(
    onPressed: (label == 'Load' || label == 'Debug')
        ? onPressed // Always enable Load and Debug
        : (label == 'Run' &&
                MainScreen.emulator.state != EmulatorState.running &&
                isCartridgeLoaded)
            ? onPressed // Enable Run if not running and cartridge is loaded
            : (label == 'Pause' &&
                    MainScreen.emulator.state == EmulatorState.running)
                ? onPressed // Enable Pause if emulator is running
                : (label == 'Reset' && isCartridgeLoaded)
                    ? onPressed // Enable Reset if cartridge is loaded
                    : null, // Disable other buttons based on conditions
    style: ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: textColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(0), // Rectangular button
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 15,
      ), // Padding
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: 'ProggyClean', // Custom font family
        fontSize: 18,
      ),
    ),
  );
}
