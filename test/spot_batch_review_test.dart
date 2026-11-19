import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/moderation/controllers/spot_batch_review.dart';
import 'package:ccs_app/features/moderation/widgets/batch_spot_review_card.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/models/spot_status.dart';

CarSpot spot(String id) => CarSpot(
  id: id,
  name: 'Review spot $id',
  cityCountry: 'Riga, Latvia',
  coordinates: const LatLng(56.9, 24.1),
  description: 'Full submission description',
  categories: ['Photo'],
  photoUrl: '',
  reelLink: '',
  bestTime: '',
  parking: '',
  roadQuality: '',
  lowCarFriendly: true,
  policeRisk: '',
  traffic: '',
  lighting: '',
  crowd: '',
  addedBy: 'driver',
  status: SpotStatus.pending,
);

void main() {
  test('no decisions are sent until every rejection has a reason', () async {
    final batch = SpotBatchReview();
    addTearDown(batch.dispose);
    batch.select(spot('a'), SpotStatus.approved);
    batch.select(spot('b'), SpotStatus.rejected);
    var sent = 0;
    expect(
      await batch.submit((_) async {
        sent++;
      }),
      0,
    );
    expect(sent, 0);
    expect(batch.errors.keys, ['b']);
    batch.reason('b', '  Inaccessible location  ');
    expect(
      await batch.submit((decision) async {
        sent++;
      }),
      2,
    );
    expect(sent, 2);
    expect(batch.drafts, isEmpty);
  });
  test(
    'partial failure retains its reason and retries only failed decisions',
    () async {
      final batch = SpotBatchReview();
      addTearDown(batch.dispose);
      batch.select(spot('a'), SpotStatus.approved);
      batch.select(spot('b'), SpotStatus.rejected);
      batch.reason('b', 'Duplicate');
      batch.select(spot('c'), SpotStatus.approved);
      final sent = <String>[];
      expect(
        await batch.submit((decision) async {
          sent.add(decision.spot.id);
          if (decision.spot.id == 'b')
            throw StateError('Another reviewer has this spot open.');
        }),
        2,
      );
      expect(sent, ['a', 'b', 'c']);
      expect(batch.drafts.keys, ['b']);
      expect(batch.drafts['b']!.reason, 'Duplicate');
      expect(batch.errors['b'], 'Another reviewer has this spot open.');
      await batch.submit((decision) async {
        sent.add(decision.spot.id);
      });
      expect(sent, ['a', 'b', 'c', 'b']);
      expect(batch.errors, isEmpty);
    },
  );
  test(
    'double submission and changing decisions while sending are blocked',
    () async {
      final batch = SpotBatchReview();
      addTearDown(batch.dispose);
      batch.select(spot('a'), SpotStatus.approved);
      final gate = Completer<void>();
      var calls = 0;
      final first = batch.submit((_) {
        calls++;
        return gate.future;
      });
      batch.select(spot('a'), SpotStatus.rejected);
      batch.clear('a');
      expect(batch.drafts['a']!.status, SpotStatus.approved);
      expect(
        await batch.submit((_) async {
          calls++;
        }),
        0,
      );
      gate.complete();
      await first;
      expect(calls, 1);
      expect(batch.busy, false);
    },
  );
  test('selecting the active choice clears it; switching keeps the reason', () {
    final batch = SpotBatchReview();
    addTearDown(batch.dispose);
    batch.select(spot('a'), SpotStatus.rejected);
    batch.reason('a', 'Reason');
    batch.select(spot('a'), SpotStatus.approved);
    batch.select(spot('a'), SpotStatus.rejected);
    expect(batch.drafts['a']!.reason, 'Reason');
    batch.select(spot('a'), SpotStatus.rejected);
    expect(batch.drafts, isEmpty);
  });
  testWidgets(
    'compact card supports editing and inline rejection without opening editor',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final batch = SpotBatchReview();
      addTearDown(batch.dispose);
      var edits = 0;
      final item = spot('a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: batch,
              builder: (_, _) => SingleChildScrollView(
                child: BatchSpotReviewCard(
                  spot: item,
                  decision: batch.drafts['a']?.status,
                  reason: batch.drafts['a']?.reason ?? '',
                  onEdit: () {
                    edits++;
                  },
                  onClear: () => batch.clear('a'),
                  onDecision: (status) => batch.select(item, status),
                  onReason: (text) => batch.reason('a', text),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(BatchSpotReviewCard)).height,
        lessThanOrEqualTo(210),
      );
      await tester.tap(find.text('Photos, map and details'));
      await tester.pumpAndSettle();
      expect(find.text('Full submission description'), findsOneWidget);
      expect(find.text('Google Maps'), findsOneWidget);
      await tester.tap(find.text('Photos, map and details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review spot a'));
      expect(edits, 1);
      await tester.ensureVisible(find.text('Reject'));
      await tester.tap(find.text('Reject'));
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(edits, 1);
      await tester.enterText(find.byType(TextFormField), 'Duplicate spot');
      expect(batch.drafts['a']!.reason, 'Duplicate spot');
      expect(tester.takeException(), isNull);
    },
  );
}
