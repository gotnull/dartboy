import 'package:flutter/material.dart';

Widget customButton({
  required String label,
  required VoidCallback onPressed, // The function to run when pressed
  Color backgroundColor = Colors.blue, // Optional: Background color
  Color textColor = Colors.white, // Optional: Text color
}) {
  return ElevatedButton(
    onPressed: onPressed,
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
