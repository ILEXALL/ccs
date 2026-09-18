import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  testWidgets('spot filters render and toggle without hidden ListTile ink', (
    tester,
  ) async {
    final categories = <String>{};
    final countries = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => app.spotFilterColumns(
              context: context,
              enabledCategories: categories,
              enabledCountries: countries,
              countries: ['LV', 'EE'],
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(categories, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  test(
    'refresh requires a server snapshot and has a bounded freshness window',
    () {
      final now = DateTime(2026, 9, 18, 12);
      expect(app.spotFeedServerSnapshotIsFresh(null, now), isFalse);
      expect(
        app.spotFeedServerSnapshotIsFresh(
          now.subtract(const Duration(seconds: 29)),
          now,
        ),
        isTrue,
      );
      expect(
        app.spotFeedServerSnapshotIsFresh(
          now.subtract(const Duration(seconds: 30)),
          now,
        ),
        isFalse,
      );
      expect(
        app.spotFeedServerSnapshotIsFresh(
          now.add(const Duration(seconds: 1)),
          now,
        ),
        isFalse,
      );
    },
  );
}
