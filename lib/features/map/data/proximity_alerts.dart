import 'dart:math' as math;

class ProximityAlert {
  const ProximityAlert(this.key, this.kind, this.distance);
  final String key, kind;
  final double distance;
}

/// One alert per approach. Jitter around 500m and filter changes do not re-alert.
class ProximityAlertTracker {
  final _announced = <String, DateTime>{};
  final _outside = <String>{};

  ProximityAlert? next({
    required List features,
    required List position,
    required double heading,
    required double speed,
    required DateTime now,
  }) {
    final candidates = <ProximityAlert>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final p = feature['properties'], geometry = feature['geometry'];
      if (p is! Map ||
          geometry is! Map ||
          !['camera', 'police'].contains(p['kind']))
        continue;
      // Keep the report visible, but never announce it to its creator.
      if (p['kind'] == 'police' && p['ownReport'] == true) continue;
      final target = geometry['coordinates'];
      if (target is! List || target.length < 2 || position.length < 2) continue;
      final lng = (target[0] as num).toDouble(),
          lat = (target[1] as num).toDouble();
      final ownLng = (position[0] as num).toDouble(),
          ownLat = (position[1] as num).toDouble();
      if (![lng, lat, ownLng, ownLat].every((v) => v.isFinite)) continue;
      final r = math.pi / 180;
      final dLat = (lat - ownLat) * r, dLng = (lng - ownLng) * r;
      final h =
          math.pow(math.sin(dLat / 2), 2) +
          math.cos(ownLat * r) *
              math.cos(lat * r) *
              math.pow(math.sin(dLng / 2), 2);
      final distance = 6371000 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
      final key = '${p['kind']}:${p['id']}';
      if (distance > 750) {
        _outside.add(key);
        continue;
      }
      if (distance > 500) continue;
      final last = _announced[key];
      if (last != null &&
          (!_outside.contains(key) ||
              now.difference(last) < const Duration(minutes: 2)))
        continue;
      if (p['kind'] == 'camera') {
        // Ahead means within a 120-degree forward cone, not behind the driver.
        if (!heading.isFinite || !speed.isFinite || speed < 1.5) continue;
        final bearing =
            math.atan2(
              math.sin(dLng) * math.cos(lat * r),
              math.cos(ownLat * r) * math.sin(lat * r) -
                  math.sin(ownLat * r) * math.cos(lat * r) * math.cos(dLng),
            ) /
            r;
        final angle = ((bearing - heading + 540) % 360) - 180;
        if (angle.abs() > 60) continue;
      }
      candidates.add(ProximityAlert(key, p['kind'] as String, distance));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    return candidates.isEmpty ? null : candidates.first;
  }

  void markPlayed(ProximityAlert alert, DateTime now) {
    _announced[alert.key] = now;
    _outside.remove(alert.key);
    if (_announced.length > 512) _announced.remove(_announced.keys.first);
    if (_outside.length > 1024) _outside.remove(_outside.first);
  }
}

String proximitySound(String kind, String language) => kind == 'camera'
    ? 'radar.mp3'
    : language == 'ru'
    ? 'police_RU.mp3'
    : 'police_ENG.mp3';
