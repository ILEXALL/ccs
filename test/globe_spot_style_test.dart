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
  test('active events keep the standard orange highlight', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final style = globeSpotStyle(
      event().copyWith(
        startsAtMillis: now - 60000,
        expiresAtMillis: now + 3600000,
        showOnMapAtMillis: now - 60000,
      ),
    );
    expect(style['event'], true);
    expect(style['color'], '#ffab40');
  });
}
