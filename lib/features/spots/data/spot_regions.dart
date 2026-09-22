import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/shared/models/countries.dart' show countryNamesByIso;

// Use the geocoder's ISO code, never the user's profile or a city-name fallback.
bool spotCountryIsSupported(String? code) {
  final normalized = code?.trim().toUpperCase();
  return countryNamesByIso.containsKey(normalized) &&
      !maintenanceModeConfig.value.bannedCountryCodes.contains(normalized);
}

const unsupportedSpotRegionMessage =
    'This region is not supported. Choose a location in an allowed country.';

const unknownSpotRegionMessage =
    'Could not verify this location’s country. Try another pin or check your connection.';

class SpotLocationRegion {
  final String? countryCode;
  final String cityCountry;
  const SpotLocationRegion(this.countryCode, this.cityCountry);
  bool get allowed => spotCountryIsSupported(countryCode);
  String get warning => countryCode == null
      ? unknownSpotRegionMessage
      : unsupportedSpotRegionMessage;
}

Future<SpotLocationRegion> lookupSpotLocationRegion(LatLng location) async {
  try {
    final places = await placemarkFromCoordinates(
      location.latitude,
      location.longitude,
    ).timeout(const Duration(seconds: 12));
    if (places.isNotEmpty) {
      final place = places.first;
      final code = place.isoCountryCode?.trim().toUpperCase();
      if (code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
        final city =
            [
                  place.locality,
                  place.subAdministrativeArea,
                  place.administrativeArea,
                ]
                .whereType<String>()
                .map((value) => value.trim())
                .firstWhere(
                  (value) => value.isNotEmpty,
                  orElse: () => 'Unknown city',
                );
        final country = countryNamesByIso[code]?.first ?? place.country ?? code;
        return SpotLocationRegion(code, '$city, $country');
      }
    }
  } catch (_) {}
  return const SpotLocationRegion(null, 'Unknown location');
}

// Generalized boundaries are visual guidance only; pin validation uses geocoding.
class SpotCountryOutline {
  final String code;
  final List<List<LatLng>> rings;
  const SpotCountryOutline(this.code, this.rings);
}

Future<List<SpotCountryOutline>>? _spotCountryOutlines;

Future<List<SpotCountryOutline>> loadSpotCountryOutlines() =>
    _spotCountryOutlines ??= rootBundle
        .loadString('assets/country_outlines.json')
        .then((source) {
          final countries = jsonDecode(source) as List<dynamic>;
          return countries
              .expand(
                (dynamic country) => (country['polygons'] as List<dynamic>).map(
                  (dynamic polygon) => SpotCountryOutline(
                    country['code'] as String,
                    (polygon as List<dynamic>)
                        .map(
                          (dynamic ring) => (ring as List<dynamic>)
                              .map(
                                (dynamic point) => LatLng(
                                  (point[1] as num).toDouble(),
                                  (point[0] as num).toDouble(),
                                ),
                              )
                              .toList(),
                        )
                        .toList(),
                  ),
                ),
              )
              .toList();
        });
