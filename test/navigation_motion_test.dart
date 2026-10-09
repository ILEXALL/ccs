import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/controllers/navigation_motion.dart';
import 'package:ccs_app/core/location/coordinates.dart';

void main() {
  test(
    'prediction keeps moving through a one-second GPS cadence and brakes on loss',
    () {
      final motion = NavigationMotion();
      motion.sample(const LatLng(57, 24), DateTime(2026), 15);
      expect(motion.distanceAhead(.9), greaterThan(motion.distanceAhead(.5)));
      expect(motion.distanceAhead(1), closeTo(15, .01));
      expect(motion.distanceAhead(3), motion.distanceAhead(30));
      expect(motion.distanceAhead(3) - motion.distanceAhead(2.9), lessThan(.1));
    },
  );
  test('stationary drift never creates speed and keeps one visual anchor', () {
    final motion = NavigationMotion();
    final start = DateTime(2026);
    const position = LatLng(57, 24);
    motion.sample(position, start, 0);
    for (var i = 1; i <= 12; i++) {
      motion.sample(
        projectLatLngMeters(position, i * 51, 5.0 + i * 3),
        start.add(Duration(seconds: i)),
        0,
      );
      expect(motion.speed, 0);
      expect(motion.distanceAhead(1), 0);
      expect(motion.stationaryPosition, position);
    }
  });
  test('one noisy moving fix cannot release stop; actual departure does', () {
    final motion = NavigationMotion();
    final start = DateTime(2026);
    const position = LatLng(57, 24);
    motion.sample(position, start, 0);
    motion.sample(
      projectLatLngMeters(position, 90, 8),
      start.add(const Duration(seconds: 1)),
      4,
    );
    expect(motion.speed, 0);
    motion.sample(position, start.add(const Duration(seconds: 2)), 0);
    expect(motion.stationaryPosition, position);
    motion.sample(
      projectLatLngMeters(position, 90, 10),
      start.add(const Duration(seconds: 3)),
      10,
    );
    expect(motion.speed, 0);
    motion.sample(
      projectLatLngMeters(position, 90, 20),
      start.add(const Duration(seconds: 4)),
      10,
    );
    expect(motion.speed, greaterThan(8));
    expect(motion.stationaryPosition, isNull);
    motion.sample(
      projectLatLngMeters(position, 90, 22),
      start.add(const Duration(seconds: 5)),
      0,
    );
    expect(motion.speed, 0);
  });
  test(
    'unavailable speed can use consecutive fixes; long gap resets stopped anchor',
    () {
      final motion = NavigationMotion();
      final start = DateTime(2026);
      const position = LatLng(57, 24);
      motion.sample(position, start, double.nan);
      for (var i = 1; i <= 2; i++) {
        motion.sample(
          projectLatLngMeters(position, 90, i * 15),
          start.add(Duration(seconds: i)),
          double.nan,
        );
      }
      expect(motion.speed, greaterThan(12));
      motion.sample(position, start.add(const Duration(seconds: 3)), 0);
      const resumed = LatLng(58, 25);
      motion.sample(resumed, start.add(const Duration(seconds: 30)), 0);
      expect(motion.stationaryPosition, resumed);
    },
  );
}
