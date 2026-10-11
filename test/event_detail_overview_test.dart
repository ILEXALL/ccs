import 'package:flutter/material.dart';
import 'package:ccs_app/shared/media/photo_gallery.dart' show SpotPhotoCarousel;
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/core/localization/app_language.dart';
import 'package:ccs_app/core/time/trusted_clock.dart';
import 'package:ccs_app/features/events/widgets/event_detail_overview.dart';
import 'group_temporary_spots_test.dart' show event;

void main() {
  testWidgets(
    'reveal bar swaps live to navigation and fails closed if time is lost',
    (tester) async {
      var opened = false;
      final spot = event().copyWith(showOnMapAtMillis: 2000000000000);
      trustedClock.setSampleForTesting(1999999999000);
      addTearDown(() => trustedClock.setSampleForTesting(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailOverview(
              spot: spot,
              onShowMap: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      trustedClock.setSampleForTesting(2000000000001);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.byIcon(Icons.navigation_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.map_outlined));
      expect(opened, isTrue);
      trustedClock.setSampleForTesting(null);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets('event overview fits narrow screen in ${language.name}', (
      tester,
    ) async {
      final previous = appUiPreferences.language;
      appUiPreferences.language = language;
      trustedClock.setSampleForTesting(1900000000000);
      addTearDown(() {
        appUiPreferences.language = previous;
        trustedClock.setSampleForTesting(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 290,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.4),
                  ),
                  child: SingleChildScrollView(
                    child: EventDetailOverview(
                      actions: const SizedBox(
                        key: ValueKey('event-actions'),
                        height: 100,
                      ),
                      spot: event().copyWith(
                        name: 'BMW meets Latvia — long event title',
                        description:
                            'A longer description that must span the full page width below the location reveal.',
                        showOnMapAtMillis: 2000000000000,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('BMW meets Latvia — long event title'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Riga, Latvia'), findsNothing);
      final poster = tester.getRect(find.byType(SpotPhotoCarousel));
      final title = tester.getRect(
        find.text('BMW meets Latvia — long event title'),
      );
      final description = tester.getRect(
        find.byKey(const ValueKey('event-full-width-description')),
      );
      final revealIcon = tester.getRect(find.byIcon(Icons.lock_outline));
      expect(poster.right, lessThan(title.left));
      final actions = tester.getRect(
        find.byKey(const ValueKey('event-actions')),
      );
      expect(actions.bottom, closeTo(poster.bottom, .1));
      expect(actions.left, closeTo(title.left, .1));
      expect(description.top, greaterThan(revealIcon.bottom));
      expect(description.width, closeTo(290, .1));
      expect(tester.takeException(), isNull);
    });
  }
}
