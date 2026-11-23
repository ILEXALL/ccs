import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:ccs_app/core/location/foreground_location_settings.dart';

/// Foreground-only country checks; never requests extra location permission.
/// Existing live-sharing GPS continues to handle permitted background fixes.
class CountryEntryTracking {
  StreamSubscription<Position>? _subscription;
  int _generation = 0;

  Future<void> start(void Function(Position) onPosition) async {
    stop();
    final generation = _generation;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse)
        return;
      if (!await Geolocator.isLocationServiceEnabled() ||
          generation != _generation)
        return;
      _subscription =
          Geolocator.getPositionStream(
            locationSettings: foregroundLocationSettings(),
          ).listen((position) {
            if (generation == _generation) onPosition(position);
          }, onError: (Object _) {});
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (generation == _generation) onPosition(position);
    } catch (_) {
      // Permission/GPS availability must never block app startup.
    }
  }

  void stop() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
