import 'package:ccs_app/features/spots/screens/creator_spots_screen.dart'
    as app
    show CreatorSpotsScreen;
import 'package:ccs_app/features/spots/widgets/creator_spots_badge.dart'
    as app
    show CreatorSpotsBadge;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ccs_app/features/events/models/event_forum_description.dart';
import 'package:ccs_app/core/network/in_flight_load.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'returning from created spots refreshes the badge synchronously',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: app.CreatorSpotsBadge(uid: '', username: 'Test driver'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.byType(app.CreatorSpotsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(app.CreatorSpotsBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('long event descriptions reserve room for dates and location', () {
    final original = 'Event information ' * 120;
    final metadata = [
      'Location: Raceway Baltic',
      'Starts at: 25.09 19:00',
      'Ends at: 25.09 23:59',
    ];
    final preview = eventForumDescription(original, metadata);
    expect(preview.length, lessThanOrEqualTo(2000));
    for (final line in metadata) {
      expect(preview, contains(line));
    }
    expect(preview, contains('…'));
    expect(
      eventForumDescription('Short description', metadata),
      'Short description\n\n${metadata.join('\n\n')}',
    );
    expect(eventForumDescription('', []), 'Event.');
  });

  test('truncation preserves emoji pairs and bounds oversized metadata', () {
    final preview = eventForumDescription('🏎' * 1100, []);
    expect(preview.length, lessThanOrEqualTo(2000));
    expect(preview.runes.where((r) => r >= 0xd800 && r <= 0xdfff), isEmpty);
    expect(eventForumDescription('Body', ['x' * 3000]).length, 2000);
  });

  test(
    'concurrent notification refreshes share work per account only',
    () async {
      final loader = InFlightLoad<String, int>();
      final pending = Completer<int>();
      var calls = 0;
      Future<int> load() {
        calls++;
        return pending.future;
      }

      final first = loader.run('alice', load);
      final second = loader.run('alice', load);
      expect(identical(first, second), isTrue);
      expect(calls, 1);
      expect(await loader.run('bob', () async => 7), 7);
      pending.complete(2);
      expect(await first, 2);
      expect(await second, 2);
      expect(await loader.run('alice', () async => 3), 3);
    },
  );

  test(
    'failed loads can retry and do not leave a rejected cached future',
    () async {
      final loader = InFlightLoad<String, int>();
      await expectLater(
        loader.run('alice', () => throw StateError('offline')),
        throwsStateError,
      );
      expect(await loader.run('alice', () async => 4), 4);
    },
  );
}
