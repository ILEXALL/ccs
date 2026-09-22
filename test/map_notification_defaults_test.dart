import 'package:ccs_app/features/map/controllers/map_start_position.dart';
import 'package:ccs_app/features/notifications/models/notification_freshness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('map fallback centres the spot extent, not Riga', () {
    final center = spotsMidpoint([const LatLng(40, 10), const LatLng(60, 30)]);
    expect(center.latitude, 50);
    expect(center.longitude, 20);
    expect(spotsMidpoint([]).latitude, 0);
    expect(spotsMidpoint([]).longitude, 0);
    expect(
      spotsMidpoint([
        const LatLng(5, 179),
        const LatLng(15, -179),
      ]).longitude.abs(),
      180,
    );
  });
  test(
    'notification startup, delayed backlog and duplicate records stay silent',
    () {
      final now = DateTime(2026, 9, 20, 12);
      final gate = NotificationFreshness(now);
      gate.seed(['initial']);
      expect(
        gate.accept('initial', now.add(const Duration(seconds: 1))),
        false,
      );
      expect(
        gate.accept(
          'old-arriving-later',
          now.subtract(const Duration(days: 1)),
        ),
        false,
      );
      expect(gate.accept('missing-date', null), false);
      expect(gate.accept('new', now.add(const Duration(seconds: 1))), true);
      expect(gate.accept('new', now.add(const Duration(seconds: 1))), false);
    },
  );
}
