import 'package:ccs_app/core/location/foreground_location_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ccs_app/features/progression/data/country_entry_tracking.dart';
import 'dart:async';

class CountryLocationPlatform extends GeolocatorPlatform {
  LocationSettings? requested;
  final positions = StreamController<Position>.broadcast();
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    requested = locationSettings;
    return positions.stream;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Future.error(StateError('No initial cached position'));
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('first Android stream subscriber requests navigation cadence', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final settings = foregroundLocationSettings() as AndroidSettings;
    expect(settings.intervalDuration, const Duration(seconds: 1));
    expect(settings.distanceFilter, 0);
    expect(settings.accuracy, LocationAccuracy.bestForNavigation);
    expect(settings.foregroundNotificationConfig, isNull);
  });
  test('iOS foreground stream cannot pause or filter driving fixes', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final settings = foregroundLocationSettings() as AppleSettings;
    expect(settings.distanceFilter, 0);
    expect(settings.pauseLocationUpdatesAutomatically, false);
    expect(settings.activityType, ActivityType.automotiveNavigation);
  });
  test(
    'country tracker cannot claim the cached stream at five-second cadence',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final original = GeolocatorPlatform.instance;
      final platform = CountryLocationPlatform();
      GeolocatorPlatform.instance = platform;
      final tracker = CountryEntryTracking();
      try {
        await tracker.start((_) {});
        final settings = platform.requested as AndroidSettings;
        expect(settings.intervalDuration, const Duration(seconds: 1));
        expect(settings.distanceFilter, 0);
        expect(platform.positions.hasListener, isTrue);
        tracker.stop();
        await Future<void>.delayed(Duration.zero);
        expect(platform.positions.hasListener, isFalse);
      } finally {
        tracker.stop();
        GeolocatorPlatform.instance = original;
        await platform.positions.close();
      }
    },
  );
}
