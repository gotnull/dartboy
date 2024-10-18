import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/gui/main_screen.dart';
import 'package:flutter/material.dart';

TextStyle proggyTextStyle({Color? color = Colors.white}) {
  return TextStyle(
    color: color,
    fontFamily: 'ProggyClean', // Custom font family
    fontSize: 18,
  );
}

Widget customButton({
  required CPU? cpu,
  required String label,
  VoidCallback? onPressed, // The function to run when pressed
  Color backgroundColor = Colors.blue, // Optional: Background color
  Color textColor = Colors.white, // Optional: Text color
}) {
  bool isCartridgeLoaded = cpu != null && cpu.cartridge.data.isNotEmpty;

  return ElevatedButton(
    onPressed: (label == 'Load' || label == 'Debug' || label == 'Save Audio')
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
      padding: const EdgeInsets.all(0), // Outer padding removed
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 8,
      ),
      child: Text(
        label,
        style: proggyTextStyle(),
      ),
    ),
  );
}

Widget dropdownButton({
  required CPU? cpu,
  required Map<String, String> romMap, // Map of display name and rom path
  ValueChanged<String?>? onChanged, // Callback when a rom is selected
}) {
  String dropdownValue = romMap.keys.first; // Start with the first ROM name

  return Container(
    decoration: BoxDecoration(
      color: Colors.blue, // Set background color to blue
      borderRadius: BorderRadius.circular(0), // Match button's border radius
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: DropdownButton<String>(
      dropdownColor: Colors.blue, // Background color for the dropdown
      value: dropdownValue, // Selected display name (ROM name)
      icon: const Icon(
        Icons.arrow_drop_down,
        color: Colors.white,
      ), // White dropdown icon
      elevation: 16,
      style: const TextStyle(
        fontFamily: 'ProggyClean', // Custom font family
        fontSize: 18,
        color: Colors.white, // White text in the dropdown
      ),
      underline: Container(), // Remove the default underline
      onChanged: (String? newValue) {
        // Get the associated ROM folder path from the selected ROM name
        String? romFolderPath = romMap[newValue!];
        onChanged?.call(romFolderPath); // Pass the ROM folder path
      },
      items: romMap.keys.map<DropdownMenuItem<String>>(
        (String romName) {
          return DropdownMenuItem<String>(
            value: romName,
            child: Text(
              romName,
              style: const TextStyle(
                color: Colors.white,
              ), // White text for each ROM name
            ),
          );
        },
      ).toList(),
    ),
  );
}
