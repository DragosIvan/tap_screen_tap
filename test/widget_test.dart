import 'package:flutter_test/flutter_test.dart';
import 'package:tap_screen_tap/main.dart';

void main() {
  testWidgets('App loads onboarding', (WidgetTester tester) async {
    await tester.pumpWidget(const TapScreenTapApp());
    expect(find.text('Tap Screen Tap'), findsOneWidget);
  });
}
