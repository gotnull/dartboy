import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/emulator.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/gui/button.dart';
import 'package:dartboy/gui/lcd.dart';
import 'package:dartboy/gui/modal.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({required Key key, required this.title}) : super(key: key);

  final String title;

  /// Emulator instance
  static Emulator emulator = Emulator();

  static LCDState lcdState = LCDState();

  static bool keyboardHandlerCreated = false;
  @override
  MainScreenState createState() {
    return MainScreenState();
  }
}

class MainScreenState extends State<MainScreen> {
  static const int keyI = 73;
  static const int keyO = 79;
  static const int keyP = 80;

  static Map<int, int> keyMapping = {
    // Left arrow
    263: Gamepad.left,
    // Right arrow
    262: Gamepad.right,
    // Up arrow
    265: Gamepad.up,
    // Down arrow
    264: Gamepad.down,
    // Z
    90: Gamepad.A,
    // X
    88: Gamepad.B,
    // Enter
    257: Gamepad.start,
    // C
    67: Gamepad.select
  };

  Future<void> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose ROM',
      withData: true, // This ensures that the file bytes are loaded into memory
    );

    if (!mounted) {
      return; // Ensure that the widget is still mounted before using the context
    }

    if (result != null && result.files.single.bytes != null) {
      MainScreen.emulator.loadROM(result.files.single.bytes!);
    } else {
      // Ensure the widget is still mounted before calling context
      Modal.alert(context, 'Error', 'No valid ROM file selected.',
          onCancel: () => {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MainScreen.keyboardHandlerCreated) {
      MainScreen.keyboardHandlerCreated = true;

      HardwareKeyboard.instance.addHandler((KeyEvent key) {
        int keyCode = key.logicalKey.keyId;

        // Debug functions
        if (MainScreen.emulator.state == EmulatorState.running) {
          if (key is KeyDownEvent) {
            if (keyCode == keyI) {
              print('Toggle background layer.');
              Configuration.drawBackgroundLayer =
                  !Configuration.drawBackgroundLayer;
              return true; // Event handled
            } else if (keyCode == keyO) {
              print('Toggle sprite layer.');
              Configuration.drawSpriteLayer = !Configuration.drawSpriteLayer;
              return true; // Event handled
            }
          }
        }

        // If the key is not found in keyMapping, return false.
        if (!keyMapping.containsKey(keyCode)) {
          return false; // Key not handled
        }

        if (key is KeyUpEvent) {
          MainScreen.emulator.buttonUp(keyMapping[keyCode]!);
          return true; // Event handled
        } else if (key is KeyDownEvent) {
          MainScreen.emulator.buttonDown(keyMapping[keyCode]!);
          return true; // Event handled
        }

        return false; // Default return value for unhandled events
      });
    }

    return Scaffold(
        backgroundColor: Colors.black,
        body: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // LCD
              const Expanded(child: LCDWidget(key: Key('lcd'))),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                    // Buttons (DPAD + AB)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        // DPAD
                        Column(
                          children: <Widget>[
                            Button(
                                color: Colors.blueAccent,
                                onPressed: () {
                                  MainScreen.emulator.buttonDown(Gamepad.up);
                                },
                                onReleased: () {
                                  MainScreen.emulator.buttonUp(Gamepad.up);
                                },
                                label: "Up",
                                key: const Key('up')),
                            Row(children: <Widget>[
                              Button(
                                  color: Colors.blueAccent,
                                  onPressed: () {
                                    MainScreen.emulator
                                        .buttonDown(Gamepad.left);
                                  },
                                  onReleased: () {
                                    MainScreen.emulator.buttonUp(Gamepad.left);
                                  },
                                  label: "Left",
                                  key: const Key('left')),
                              const SizedBox(width: 50, height: 50),
                              Button(
                                  color: Colors.blueAccent,
                                  onPressed: () {
                                    MainScreen.emulator
                                        .buttonDown(Gamepad.right);
                                  },
                                  onReleased: () {
                                    MainScreen.emulator.buttonUp(Gamepad.right);
                                  },
                                  label: "Right",
                                  key: const Key('right'))
                            ]),
                            Button(
                                color: Colors.blueAccent,
                                onPressed: () {
                                  MainScreen.emulator.buttonDown(Gamepad.down);
                                },
                                onReleased: () {
                                  MainScreen.emulator.buttonUp(Gamepad.down);
                                },
                                label: "Down",
                                key: const Key('down')),
                          ],
                        ),
                        // AB
                        Column(
                          children: <Widget>[
                            Button(
                                color: Colors.red,
                                onPressed: () {
                                  MainScreen.emulator.buttonDown(Gamepad.A);
                                },
                                onReleased: () {
                                  MainScreen.emulator.buttonUp(Gamepad.A);
                                },
                                label: "A",
                                key: const Key('a')),
                            Button(
                                color: Colors.green,
                                onPressed: () {
                                  MainScreen.emulator.buttonDown(Gamepad.B);
                                },
                                onReleased: () {
                                  MainScreen.emulator.buttonUp(Gamepad.B);
                                },
                                label: "B",
                                key: const Key('b')),
                          ],
                        ),
                      ],
                    ),
                    // Button (SELECT + START)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Button(
                            color: Colors.orange,
                            onPressed: () {
                              MainScreen.emulator.buttonDown(Gamepad.start);
                            },
                            onReleased: () {
                              MainScreen.emulator.buttonUp(Gamepad.start);
                            },
                            labelColor: Colors.black,
                            label: "Start",
                            key: const Key('start')),
                        Container(width: 20),
                        Button(
                            color: Colors.yellowAccent,
                            onPressed: () {
                              MainScreen.emulator.buttonDown(Gamepad.select);
                            },
                            onReleased: () {
                              MainScreen.emulator.buttonUp(Gamepad.select);
                            },
                            labelColor: Colors.black,
                            label: "Select",
                            key: const Key('select')),
                      ],
                    ),
                    // Button (Start + Pause + Load)
                    Expanded(
                        child: ListView(
                      padding: const EdgeInsets.only(left: 10.0, right: 10.0),
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        ElevatedButton(
                            onPressed: () {
                              if (MainScreen.emulator.state !=
                                  EmulatorState.ready) {
                                Modal.alert(
                                  context,
                                  'Error',
                                  'Not ready to run. Load ROM first.',
                                  onCancel: () => {},
                                );
                                return;
                              }
                              MainScreen.emulator.run();
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor:
                                  Colors.black, // Button background color
                            ),
                            child: const Text('Run',
                                style: TextStyle(color: Colors.white))),
                        ElevatedButton(
                            onPressed: () {
                              if (MainScreen.emulator.state !=
                                  EmulatorState.running) {
                                Modal.alert(context, 'Error',
                                    "Not running can't be paused.",
                                    onCancel: () => {});
                                return;
                              }

                              MainScreen.emulator.pause();
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor:
                                  Colors.black, // Button background color
                            ),
                            child: const Text('Pause',
                                style: TextStyle(color: Colors.white))),
                        ElevatedButton(
                            onPressed: () {
                              MainScreen.emulator.reset();
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor:
                                  Colors.black, // Button background color
                            ),
                            child: const Text('Reset',
                                style: TextStyle(color: Colors.white))),
                        ElevatedButton(
                            onPressed: () {
                              MainScreen.emulator.debugStep();
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor:
                                  Colors.black, // Button background color
                            ),
                            child: const Text('Step',
                                style: TextStyle(color: Colors.white))),
                        ElevatedButton(
                            onPressed: () {
                              pickFile(); // Call the method when the button is pressed
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor:
                                  Colors.black, // Button background color
                            ),
                            child: const Text("Load",
                                style: TextStyle(color: Colors.white))),
                      ],
                    ))
                  ]))
            ]));
  }

  /// Show a text input dialog to introduce string values.
  textInputDialog({required String hint, required Function onOpen}) async {
    TextEditingController controller = TextEditingController();
    controller.text = hint;

    await showDialog<String>(
        context: context,
        builder: (BuildContext cx) {
          return AlertDialog(
              contentPadding: const EdgeInsets.all(16.0),
              content: Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    autofocus: true,
                    controller: controller,
                    decoration:
                        InputDecoration(labelText: 'File Name', hintText: hint),
                  ),
                )
              ]),
              actions: <Widget>[
                TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.pop(context);
                    }),
                TextButton(
                    child: const Text('Open'),
                    onPressed: () {
                      onOpen(controller.text);
                      Navigator.pop(context);
                    })
              ]);
        });
  }
}
