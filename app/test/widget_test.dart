import 'package:flutter_test/flutter_test.dart';
import 'package:wow_journey/src/app.dart';

void main() {
  testWidgets('the app shows its title', (tester) async {
    await tester.pumpWidget(const WowJourneyApp());

    expect(find.text('WoW Journey'), findsOneWidget);
  });
}
