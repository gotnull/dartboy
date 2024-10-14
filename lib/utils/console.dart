import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Console class stores static method to log information into the development console.
///
/// Provides a more complete output of the data.
class Console {
  static const bool debugPrint = true;

  /// Build a string to represent an object.
  static String build(dynamic obj, {int level = 0}) {
    try {
      JsonEncoder encoder = const JsonEncoder.withIndent("   ");
      return encoder.convert(obj);
    } catch (e) {
      print("Invalid JSON.");
    }

    return obj.toString();
  }

  /// Log a object value into the console in a JSON like structure.
  ///
  /// @param obj Object to be printed into the console.
  static void log(dynamic obj) {
    if (debugPrint) {
      debugPrintSynchronously(build(obj));
    } else {
      print(build(obj));
    }
  }

  static int logCounter = 0;
  static int logLimit = 5000; // Limit log to 5000 lines, adjust as needed

  static void logToFile(String message) {
    if (logCounter < logLimit) {
      final logFile = File("cpu_log.txt");
      logFile.writeAsStringSync("$message\n", mode: FileMode.append);
      logCounter++;
    }
  }
}
