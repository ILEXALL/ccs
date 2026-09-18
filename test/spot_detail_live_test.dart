import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;
import 'group_temporary_spots_test.dart' show event;

void main() {
  testWidgets(
    'open details adopts full edits with unchanged counters and handles deletion',
    (tester) async {
      final updates = StreamController<app.CarSpot?>();
      final original = event(visibility: 'group');
      await tester.pumpWidget(
        MaterialApp(
          home: app.SpotDetailScreen(
            spot: original,
            spotUpdates: updates.stream,
          ),
        ),
      );
      final dynamic state = tester.state(find.byType(app.SpotDetailScreen));
      final edited = original.copyWith(
        name: 'New event name',
        description: 'Updated description',
        startsAtMillis: 2000001000000,
        expiresAtMillis: 2000004600000,
      );
      updates.add(edited);
      await tester.pump();
      await tester.pump();
      expect(state.spot.name, 'New event name');
      expect(state.spot.description, 'Updated description');
      expect(state.spot.startsAtMillis, edited.startsAtMillis);
      expect(state.spot.likeCount, original.likeCount);
      expect(state.spot.commentCount, original.commentCount);
      updates.add(null);
      await tester.pump();
      await tester.pump();
      expect(find.text('This spot is no longer available.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      updates.add(edited);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      unawaited(updates.close());
    },
  );
}
