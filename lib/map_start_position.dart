import 'package:latlong2/latlong.dart';

// Midpoint of the smallest longitude span, including spots across the dateline.
LatLng spotsMidpoint(Iterable<LatLng> points) {
  final valid = points
      .where(
        (p) =>
            p.latitude.isFinite &&
            p.longitude.isFinite &&
            p.latitude.abs() <= 90 &&
            p.longitude.abs() <= 180,
      )
      .toList();
  if (valid.isEmpty) return const LatLng(0, 0);
  final latitudes = valid.map((p) => p.latitude).toList()..sort();
  final longitudes = valid.map((p) => (p.longitude + 360) % 360).toList()
    ..sort();
  double gap = -1, start = longitudes.first;
  for (var i = 0; i < longitudes.length; i++) {
    final next = i + 1 == longitudes.length
        ? longitudes.first + 360
        : longitudes[i + 1];
    if (next - longitudes[i] > gap) {
      gap = next - longitudes[i];
      start = next % 360;
    }
  }
  final longitude = (start + (360 - gap) / 2 + 180) % 360 - 180;
  return LatLng((latitudes.first + latitudes.last) / 2, longitude);
}
