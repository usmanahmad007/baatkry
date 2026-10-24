import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MonkeyOmegleApp());
    expect(find.byType(MonkeyOmegleApp), findsOneWidget);
  });
}
