import 'package:flutter/material.dart';

/// Button widget with up and down callbacks.
/// Button widget with up and down callbacks.
class Button extends StatefulWidget {
  /// Callback method executed when the button is pressed.
  final Function onPressed;

  /// Callback method executed when the button is released.
  final Function onReleased;

  /// Color of the button
  final Color color;

  /// Color of the label
  final Color labelColor;

  /// Label
  final String label;

  const Button({
    required this.label,
    required this.color,
    required this.onPressed,
    required this.onReleased,
    this.labelColor = Colors.white, // Default value for labelColor
    required Key key,
  }) : super(key: key);

  @override
  ButtonState createState() {
    return ButtonState();
  }
}

class ButtonState extends State<Button> {
  /// Indicates if the user is tapping the button.
  bool pressed = false;

  ButtonState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 0.0),
      child: InkWell(
        enableFeedback: true,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onHighlightChanged: (bool highlight) {
          if (!pressed && highlight) {
            widget.onPressed();
          }

          if (pressed && !highlight) {
            widget.onReleased();
          }

          pressed = highlight;
          setState(() {});
        },
        onTap: () {},
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 50.0,
              width: 50.0,
              decoration: BoxDecoration(
                  color: pressed ? Colors.grey : widget.color,
                  borderRadius: BorderRadius.circular(20.0)),
              child: Center(
                child: Text(
                  widget.label,
                  style: TextStyle(color: widget.labelColor),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
