import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;

/// Preserve walking scale; show three times the ground distance at 100 km/h.
double speedFollowZoom(double baseZoom, double metersPerSecond) {
  final kmh = metersPerSecond.isFinite
      ? math.max(0.0, metersPerSecond) * 3.6
      : 0.0;
  final scale = math.min(5.0, 1 + math.max(0.0, kmh - 30) / 35);
  return baseZoom - math.log(scale) / math.ln2;
}

/// Visual-only velocity estimate. Never used for uploads or visit/XP evidence.
class NavigationMotion {
  LatLng? _previous;
  DateTime? _time;
  double speed = 0;
  LatLng? stationaryPosition;
  int _movingFixes = 0;
  double _fixIntervalSeconds = 1, _deliveryDelaySeconds = 0;

  void sample(
    LatLng position,
    DateTime time,
    double gpsSpeed, {
    double? deliveryDelaySeconds,
    double accuracyMeters = 0,
    double speedAccuracy = 0,
    LatLng? stationaryAnchor,
  }) {
    if (_time == time) return;
    final seconds = _time == null
        ? 0.0
        : time.difference(_time!).inMilliseconds / 1000;
    // The OS requests one-second fixes, but may deliver them less frequently.
    // Learn that cadence rather than braking at every ordinary delayed fix.
    if (seconds >= .25 && seconds <= 5) {
      _fixIntervalSeconds = math.max(
        seconds,
        _fixIntervalSeconds + (seconds - _fixIntervalSeconds) * .25,
      );
    }
    if (deliveryDelaySeconds != null && deliveryDelaySeconds.isFinite) {
      _deliveryDelaySeconds = deliveryDelaySeconds.clamp(0.0, 2.0);
    }
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
    if (stationaryPosition != null && target >= .8) {
      final uncertainty = accuracyMeters.isFinite
          ? accuracyMeters.clamp(0.0, 16.0) * .5
          : 8.0;
      final awayFromStop = distanceBetweenLatLngMeters(
        stationaryPosition!,
        position,
      );
      final speedError = speedAccuracy.isFinite
          ? math.max(0.0, speedAccuracy)
          : 0.0;
      // Two small speed spikes inside the GPS uncertainty circle are not a
      // departure. Require both displacement and usable motion evidence.
      if (awayFromStop < math.max(3.0, uncertainty) ||
          (hasReportedSpeed && reported - speedError < .8)) {
        target = 0;
      }
    }
    _movingFixes = target >= .8 ? _movingFixes + 1 : 0;
    // Require two consecutive moving fixes after a stop, not one noisy sample.
    if (_time != null && speed < .8 && _movingFixes < 2) target = 0;
    if (target < .8) {
      // Release an old anchor after a long GPS gap (for example app resume).
      if (stationaryPosition == null || seconds > 10 || seconds <= 0) {
        stationaryPosition = seconds > 10
            ? position
            : (stationaryAnchor ?? position);
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

  /// Coast through the observed fix cadence and delivery delay, then brake.
  /// Even a slow receiver cannot extrapolate beyond five seconds without GPS.
  double distanceAhead(double ageSeconds) {
    if (!ageSeconds.isFinite || speed < .8) return 0;
    final coastUntil = (_fixIntervalSeconds + _deliveryDelaySeconds + .5).clamp(
      1.5,
      3.5,
    );
    final age = ageSeconds.clamp(0.0, coastUntil + 1.5);
    final coast = math.min(age, coastUntil);
    final braking = (age - coastUntil).clamp(0.0, 1.5);
    return speed * (coast + braking - braking * braking / 3);
  }
}
