import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/main.dart' as app;
import 'group_temporary_spots_test.dart' show event;

void main() {
  setUp(() {
    final countries = app.spotCountryFilters.value;
    final categories = app.spotCategoryFilters.value;
    addTearDown(() {
      app.spotCountryFilters.value = countries;
      app.spotCategoryFilters.value = categories;
    });
    app.spotCountryFilters.value = {'Latvia'};
    app.spotCategoryFilters.value = {'Meet'};
  });

  test('all 600 spots survive density and geographic distance', () {
    final spots = List.generate(
      600,
      (i) => event().copyWith(
        id: 'spot-$i',
        isTemporary: false,
        coordinates: LatLng(56, 21 + i / 100),
      ),
    );
    expect(app.mapVisibleSpots(spots).map((s) => s.id), spots.map((s) => s.id));
    final submitted = event().copyWith(id: 'new', isTemporary: false);
    expect(app.mapVisibleSpots([...spots, submitted]), contains(submitted));
  });

  test('nearby temporary events never suppress permanent spots', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final permanent = event().copyWith(id: 'permanent', isTemporary: false);
    final temporary = event().copyWith(
      startsAtMillis: now - 60000,
      expiresAtMillis: now + 3600000,
      showOnMapAtMillis: now - 60000,
    );
    expect(app.mapVisibleSpots([permanent, temporary]), [permanent, temporary]);
    expect(app.mapVisibleSpots([permanent]), [permanent]);
  });

  test('moderation, filters, expiry and scheduled location privacy remain', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final spot = event().copyWith(isTemporary: false);
    expect(
      app.mapVisibleSpots([
        spot.copyWith(status: app.SpotStatus.pending),
        spot.copyWith(countryCode: 'EE', cityCountry: 'Tallinn, Estonia'),
        spot.copyWith(categories: ['Photo']),
        event().copyWith(
          startsAtMillis: now - 120000,
          expiresAtMillis: now - 60000,
          showOnMapAtMillis: now - 120000,
        ),
        event().copyWith(
          startsAtMillis: now + 120000,
          expiresAtMillis: now + 3600000,
          showOnMapAtMillis: now + 60000,
        ),
        spot.copyWith(coordinates: const LatLng(double.nan, 24)),
      ]),
      isEmpty,
    );
    app.spotCategoryFilters.value = {};
    expect(app.mapVisibleSpots([spot]), isEmpty);
  });
}
