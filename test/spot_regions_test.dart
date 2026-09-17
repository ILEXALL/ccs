import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

class FakeGeocoder extends GeocodingPlatform {
  List<Placemark> places = [];
  bool fail = false;
  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    if (fail) throw Exception('offline');
    return places;
  }
}

void main() {
  test(
    'geocoder uses ISO despite localized names and rejects unavailable country',
    () async {
      final previousGeocoder = GeocodingPlatform.instance;
      final fake = FakeGeocoder();
      GeocodingPlatform.instance = fake;
      try {
        app.maintenanceModeConfig.value = app.MaintenanceModeConfig.disabled;
        fake.places = [
          const Placemark(
            isoCountryCode: 'LV',
            country: 'Latvija',
            locality: 'Rīga',
          ),
        ];
        final region = await app.lookupSpotLocationRegion(
          const LatLng(56.95, 24.1),
        );
        expect(region.allowed, isTrue);
        expect(region.cityCountry, 'Rīga, Latvia');
        fake.places = [const Placemark(isoCountryCode: 'EG', country: 'Egypt')];
        expect(
          (await app.lookupSpotLocationRegion(const LatLng(30, 31))).allowed,
          isFalse,
        );
        fake.places = [const Placemark(country: 'Latvia')];
        expect(
          (await app.lookupSpotLocationRegion(
            const LatLng(56.95, 24.1),
          )).countryCode,
          isNull,
        );
        fake.places = [];
        expect(
          (await app.lookupSpotLocationRegion(const LatLng(0, 0))).allowed,
          isFalse,
        );
        fake.fail = true;
        expect(
          (await app.lookupSpotLocationRegion(const LatLng(0, 0))).allowed,
          isFalse,
        );
      } finally {
        if (previousGeocoder != null)
          GeocodingPlatform.instance = previousGeocoder;
      }
    },
  );
  final previous = app.maintenanceModeConfig.value;
  tearDown(() => app.maintenanceModeConfig.value = previous);
  test('only listed and unrestricted countries accept new spots', () {
    app.maintenanceModeConfig.value = app.MaintenanceModeConfig.disabled;
    expect(app.spotCountryIsSupported('LV'), isTrue);
    expect(app.spotCountryIsSupported(' ee '), isTrue);
    for (final code in [null, '', 'ZZ', 'EG', 'Latvia']) {
      expect(app.spotCountryIsSupported(code), isFalse, reason: '$code');
    }
    app.maintenanceModeConfig.value = const app.MaintenanceModeConfig(
      maintenanceEnabled: false,
      maintenanceTitle: '',
      maintenanceMessage: '',
      allowAdminBypass: true,
      minimumAppVersion: '',
      updateContact: '',
      bannedCountryCodes: {'LV'},
    );
    expect(app.spotCountryIsSupported('LV'), isFalse);
    expect(app.spotCountryIsSupported('EE'), isTrue);
  });
  test(
    'existing selection follows restriction changes and unknown fails closed',
    () {
      app.maintenanceModeConfig.value = app.MaintenanceModeConfig.disabled;
      const region = app.SpotLocationRegion('LV', 'Riga, Latvia');
      expect(region.allowed, isTrue);
      app.maintenanceModeConfig.value = const app.MaintenanceModeConfig(
        maintenanceEnabled: false,
        maintenanceTitle: '',
        maintenanceMessage: '',
        allowAdminBypass: false,
        minimumAppVersion: '',
        updateContact: '',
        bannedCountryCodes: {'LV'},
      );
      expect(region.allowed, isFalse);
      expect(region.warning, app.unsupportedSpotRegionMessage);
      const unknown = app.SpotLocationRegion(null, 'Unknown location');
      expect(unknown.allowed, isFalse);
      expect(unknown.warning, app.unknownSpotRegionMessage);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled country outlines load with valid rings and ISO mappings',
    () async {
      final outlines = await app.loadSpotCountryOutlines();
      expect(
        outlines.map((o) => o.code),
        containsAll(['LV', 'EE', 'FR', 'NO', 'RU', 'EG']),
      );
      for (final outline in outlines) {
        expect(outline.rings, isNotEmpty);
        expect(outline.rings.first.length, greaterThanOrEqualTo(4));
        for (final ring in outline.rings) {
          for (final point in ring) {
            expect(point.latitude, inInclusiveRange(-90, 90));
            expect(point.longitude, inInclusiveRange(-180, 180));
          }
        }
      }
    },
  );
}
