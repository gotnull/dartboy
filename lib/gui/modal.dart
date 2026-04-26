import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class Modal {
  /// Show a alert modal
  ///
  /// The onCancel callbacks receive BuildContext context as argument.
  static void alert(
    BuildContext context,
    String title,
    String message, {
    required Function onCancel,
  }) {
    showFDialog(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style,
        animation: animation,
        title: Text(title),
        body: Text(message),
        actions: [
          FButton(
            onPress: () {
              Navigator.pop(context);
              onCancel();
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
