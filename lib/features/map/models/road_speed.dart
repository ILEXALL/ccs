/// Raw GPS only: predicted marker motion must never drive speed warnings.
class RoadGpsSpeed {
  static double? kilometersPerHour(Map? fix, DateTime now) {
    if (fix == null || fix['mocked'] != false) return null;
    final at = fix['at'], speed = fix['speed'];
    final accuracy = fix['accuracy'], speedAccuracy = fix['speedAccuracy'];
    if (at is! num ||
        speed is! num ||
        accuracy is! num ||
        speedAccuracy is! num) {
      return null;
    }
    final age = now.millisecondsSinceEpoch - at;
    if (age < 0 ||
        age > 5000 ||
        !speed.isFinite ||
        speed < 0 ||
        speed > 100 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 25 ||
        !speedAccuracy.isFinite ||
        speedAccuracy < 0 ||
        speedAccuracy > 2) {
      return null;
    }
    return speed * 3.6;
  }
}

/// Provider adapters must resolve direction, vehicle and conditional rules,
/// reject ambiguous/parallel-road matches, and invalidate on road changes.
/// Missing provider data stays unavailable; legal defaults are never guessed.
class ApplicableRoadLimit {
  const ApplicableRoadLimit({
    required this.kilometersPerHour,
    required this.validUntil,
    required this.source,
    required this.roadId,
    required this.applicabilityVerified,
    required this.unambiguousMatch,
  });
  final double kilometersPerHour;
  final DateTime validUntil;
  final String source, roadId;
  final bool applicabilityVerified, unambiguousMatch;
  bool usableAt(DateTime now) =>
      applicabilityVerified &&
      unambiguousMatch &&
      source.isNotEmpty &&
      roadId.isNotEmpty &&
      kilometersPerHour.isFinite &&
      kilometersPerHour > 0 &&
      validUntil.isAfter(now);
  bool isOverspeed(double? gpsKmh, DateTime now) =>
      usableAt(now) &&
      gpsKmh != null &&
      gpsKmh.isFinite &&
      gpsKmh > kilometersPerHour;
}
