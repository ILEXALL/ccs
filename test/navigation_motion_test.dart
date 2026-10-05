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
  test(
    'speed derives from fixes when unavailable, while small stationary drift stays still',
    () {
      final motion = NavigationMotion();
      final start = DateTime(2026);
      const position = LatLng(57, 24);
      motion.sample(position, start, 0);
      motion.sample(
        projectLatLngMeters(position, 90, 15),
        start.add(const Duration(seconds: 1)),
        0,
      );
      expect(motion.speed, greaterThan(12));
      motion.sample(
        projectLatLngMeters(position, 90, 16),
        start.add(const Duration(seconds: 2)),
        0,
      );
      expect(motion.speed, 0);
      motion.sample(
        const LatLng(58, 25),
        start.add(const Duration(seconds: 3)),
        0,
      );
      expect(motion.speed, 0);
    },
  );
}
