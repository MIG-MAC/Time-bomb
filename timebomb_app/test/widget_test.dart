import 'package:flutter_test/flutter_test.dart';
import 'package:timebomb_app/main.dart';

void main() {
  testWidgets('Counter increment smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TimeBombApp());

    // Verify that our app starts on the Home Screen.
    expect(find.text('TIME BOMB'), findsOneWidget);
  });
}
