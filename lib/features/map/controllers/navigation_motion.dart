import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;

/// Visual-only velocity estimate. Never used for uploads or visit/XP evidence.
class NavigationMotion {
  LatLng? _previous;
  DateTime? _time;
  double speed = 0;
  LatLng? stationaryPosition;
  int _movingFixes = 0;

  void sample(LatLng position, DateTime time, double gpsSpeed) {
    if (_time == time) return;
    final seconds = _time == null
        ? 0.0
        : time.difference(_time!).inMilliseconds / 1000;
    final distance = _previous == null
        ? 0.0
        : distanceBetweenLatLngMeters(_previous!, position);
    final measured = seconds >= .25 && seconds <= 3 ? distance / seconds : 0.0;
    final hasReportedSpeed = gpsSpeed.isFinite && gpsSpeed >= 0;
    final reported = hasReportedSpeed
        ? gpsSpeed.clamp(0.0, 70.0).toDouble()
        : 0.0;
    // Avoid interpreting stationary GPS noise or a reacquisition jump as driving.
    final usableCourse = measured >= 2 && measured <= 70 && distance >= 4;
    // Zero is a valid stopped reading, not an unavailable speed. GPS drift
    // must not manufacture forward velocity while the receiver says stopped.
    var target = hasReportedSpeed
        ? (reported >= .8
              ? (usableCourse ? reported * .7 + measured * .3 : reported)
              : 0.0)
        : (usableCourse && measured >= 3 ? measured : 0.0);
    _movingFixes = target >= .8 ? _movingFixes + 1 : 0;
    // Require two consecutive moving fixes after a stop, not one noisy sample.
    if (_time != null && speed < .8 && _movingFixes < 2) target = 0;
    if (target < .8) {
      // Release an old anchor after a long GPS gap (for example app resume).
      if (stationaryPosition == null || seconds > 10 || seconds <= 0) {
        stationaryPosition = position;
      }
    } else {
      stationaryPosition = null;
    }
    if (_time == null || seconds > 3 || seconds <= 0 || target < .8) {
      speed = target;
    } else {
      speed += (target - speed) * (1 - math.exp(-seconds / .45));
    }
    _previous = position;
    _time = time;
  }

  /// Predict through a normal one-second fix interval, then smoothly brake.
  /// The integral stops growing after three seconds without a fresh fix.
  double distanceAhead(double ageSeconds) {
    if (!ageSeconds.isFinite || speed < .8) return 0;
    final age = ageSeconds.clamp(0.0, 3.0);
    final coast = math.min(age, 1.5);
    final braking = (age - 1.5).clamp(0.0, 1.5);
    return speed * (coast + braking - braking * braking / 3);
  }
}
