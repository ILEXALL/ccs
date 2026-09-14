import 'package:latlong2/latlong.dart';

const spotPresenceRadiusMeters = 100.0;
const spotPresenceFreshness = Duration(seconds: 150);

class PresencePoint {
  final String id;
  final LatLng position;
  final int updatedAt;
  final int expiresAt;
  const PresencePoint(this.id, this.position, this.updatedAt, this.expiresAt);
}

// Input people must already be filtered by the viewer's location permissions.
// Assign each person to one nearest visible spot, not every overlapping radius.
Map<String, List<String>> groupSpotPresence(
  Map<String, LatLng> spots, Iterable<PresencePoint> people, int now,
) {
  const distance = Distance(roundResult: false, calculator: Haversine());
  bool valid(LatLng p) => p.latitude.isFinite && p.longitude.isFinite &&
      p.latitude.abs() <= 90 && p.longitude.abs() <= 180;
  final result = <String, List<String>>{};
  final seen = <String>{};
  final sortedSpots = spots.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final person in people) {
    if (!valid(person.position) || person.updatedAt <= 0 || person.updatedAt > now || person.expiresAt <= now ||
        now - person.updatedAt > spotPresenceFreshness.inMilliseconds || !seen.add(person.id)) {
      continue;
    }
    String? nearest;
    var minimum = spotPresenceRadiusMeters + .000001;
    for (final spot in sortedSpots) {
      if (!valid(spot.value)) continue;
      final meters = distance.as(LengthUnit.Meter, person.position, spot.value);
      if (meters < minimum) { minimum = meters; nearest = spot.key; }
    }
    if (nearest != null) (result[nearest] ??= []).add(person.id);
  }
  for (final ids in result.values) { ids.sort(); }
  return result;
}
