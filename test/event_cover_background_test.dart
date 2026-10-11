import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/events/widgets/event_cover_background.dart';
import 'group_temporary_spots_test.dart' show event;

void main() {
  testWidgets(
    'coverless event keeps readable fallback and interactive content',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventCoverBackground(
              spot: event().copyWith(photoUrl: '', photoUrls: []),
              child: Center(
                child: TextButton(
                  onPressed: () => tapped = true,
                  child: const Text('Open event'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open event'));
      expect(tapped, isTrue);
      expect(find.byType(DecoratedBox), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('permanent spots keep their existing background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCoverBackground(
            spot: event().copyWith(isTemporary: false),
            child: const Text('Regular spot'),
          ),
        ),
      ),
    );
    expect(find.text('Regular spot'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
