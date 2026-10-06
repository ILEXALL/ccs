import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/data/country_capitals.dart';
import 'package:ccs_app/shared/models/countries.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';

void main() {
  test(
    'every selectable profile country has a capital, including localized names',
    () {
      expect(countryCapitals.keys.toSet(), countryNamesByIso.keys.toSet());
      expect(capitalForProfileCountry('Latvija'), countryCapitals['LV']);
      expect(capitalForProfileCountry('Германия'), countryCapitals['DE']);
      expect(capitalForProfileCountry('United Kingdom'), countryCapitals['GB']);
    },
  );
  test(
    'regional overview preserves roughly 60000 square km on phones and tablets',
    () {
      for (final size in [
        [390.0, 650.0],
        [768.0, 900.0],
      ]) {
        for (final capital in countryCapitals.values) {
          final zoom = regionalOverviewZoom(size[0], size[1], capital.latitude);
          final resolution =
              78271.51696 *
              math.cos(capital.latitude * math.pi / 180) /
              math.pow(2, zoom);
          expect(
            resolution * resolution * size[0] * size[1] / 1000000,
            closeTo(60000, 1),
          );
        }
      }
    },
  );
}
