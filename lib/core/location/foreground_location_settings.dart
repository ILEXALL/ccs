import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Geolocator caches one platform position stream: the first subscriber's
/// settings also apply to later subscribers. Country tracking starts before
/// the map, so both must request navigation cadence instead of allowing the
/// Android default (five seconds) to throttle Follow.
LocationSettings foregroundLocationSettings() {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      forceLocationManager: false,
    );
  }
  return AppleSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    activityType: ActivityType.automotiveNavigation,
    pauseLocationUpdatesAutomatically: false,
  );
}
