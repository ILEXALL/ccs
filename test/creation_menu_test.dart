import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  testWidgets('creation menu separates permanent spots from events', (
    tester,
  ) async {
    bool? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selection = await app.showCreationMenu(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Add Spot'), findsOneWidget);
    expect(find.text('Add Event'), findsOneWidget);
    await tester.tap(find.text('Add Event'));
    await tester.pumpAndSettle();
    expect(selection, isTrue);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Spot'));
    await tester.pumpAndSettle();
    expect(selection, isFalse);
  });
  testWidgets(
    'only the Event creation page has a schedule, without a type toggle',
    (tester) async {
      for (final eventMode in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: app.AddSpotScreen(
              key: ValueKey(eventMode),
              eventMode: eventMode,
            ),
          ),
        );
        await tester.pump();
        final dynamic state = tester.state(find.byType(app.AddSpotScreen));
        expect(state.isTemporarySpot, eventMode);
        expect(find.text(eventMode ? 'Add Event' : 'Add Spot'), findsOneWidget);
        if (eventMode) {
          await tester.scrollUntilVisible(
            find.text('Event schedule'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Temporary spot'), findsNothing);
          expect(find.widgetWithText(SwitchListTile, 'Event'), findsNothing);
        } else {
          expect(find.text('Event schedule'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
