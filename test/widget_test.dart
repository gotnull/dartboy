import 'package:dartboy/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("DartBoy renders the emulator shell",
      (WidgetTester tester) async {
    await tester.pumpWidget(const DartBoy());
    await tester.pump();

    expect(find.byKey(const Key("dartBoy")), findsOneWidget);
    expect(find.byKey(const Key("lcd")), findsOneWidget);
    expect(find.text("DartBoy"), findsOneWidget);
  });
}
