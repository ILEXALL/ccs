import 'package:ccs_app/core/time/trusted_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/models/globe_spot_style.dart';
import 'package:ccs_app/features/spots/models/spot_categories.dart';
import 'group_temporary_spots_test.dart' show event;

void main() {
  test('every category uses the same original artwork and color', () {
    for (final category in spotCategoryOptions) {
      final spot = event().copyWith(isTemporary: false, categories: [category]);
      final style = globeSpotStyle(spot);
      expect(style['icon'], spotCategoryIconAssets[category]);
      expect(
        style['color'],
        '#${(spotCategoryColors[category]!.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
      );
    }
  });
  test('active events use golden artwork and highlight', () {
    const now = 2000000060000;
    trustedClock.setSampleForTesting(now);
    addTearDown(() => trustedClock.setSampleForTesting(null));
    final style = globeSpotStyle(
      event().copyWith(
        startsAtMillis: now - 60000,
        expiresAtMillis: now + 3600000,
        showOnMapAtMillis: now - 60000,
      ),
    );
    expect(style['event'], true);
    expect(style['eventActive'], true);
    expect(style['eventStartLabel'], isNotEmpty);
    expect(style['color'], '#ffd45a');
    expect(style['tint'], false);
    expect(style['opacity'], 1.0);
  });
  test('revealed future event is golden with start badge but no waves', () {
    const now = 2000000060000;
    trustedClock.setSampleForTesting(now);
    addTearDown(() => trustedClock.setSampleForTesting(null));
    final spot = event().copyWith(
      startsAtMillis: now + 3600000,
      expiresAtMillis: now + 7200000,
      showOnMapAtMillis: now - 1000,
    );
    final style = globeSpotStyle(spot);
    expect(style['event'], true);
    expect(style['eventActive'], false);
    expect(style['opacity'], 1.0);
    expect(style['tint'], false);
    expect(style['eventStartLabel'], isNotEmpty);
    expect(style['color'], '#ffd45a');
    expect(spot.hasOpeningHours, false);
  });
}
