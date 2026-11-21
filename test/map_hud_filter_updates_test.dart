import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/widgets/road_speed_hud.dart';
import 'package:ccs_app/features/spots/widgets/spot_filter_panel.dart';

void main() {
  testWidgets('speed HUD hides below 10 and reappears at the threshold', (
    tester,
  ) async {
    for (final speed in <double?>[null, double.nan, 0, 9.99, 10, 55, 5]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RoadSpeedHud(speedKmh: speed)),
        ),
      );
      expect(
        find.text('km/h'),
        speed != null && speed.isFinite && speed >= 10
            ? findsOneWidget
            : findsNothing,
      );
    }
  });
  testWidgets(
    'filter tabs use switches and preserve category and country selections',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final categories = <String>{};
      final countries = <String>{'Latvia', 'Lithuania'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => spotFilterColumns(
                context: context,
                enabledCategories: categories,
                enabledCountries: countries,
                countries: ['Latvia', 'Lithuania'],
                onChanged: () => update(() {}),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(categories.length, 1);
      await tester.tap(find.byType(Tab).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(countries, {'Lithuania'});
      await tester.tap(find.byType(SwitchListTile).last);
      await tester.pumpAndSettle();
      expect(countries, {'Lithuania'});
      expect(tester.takeException(), isNull);
    },
  );
}
