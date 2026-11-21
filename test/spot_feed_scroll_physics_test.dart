import 'package:ccs_app/features/spots/widgets/spot_feed_scroll_physics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 10000,
    pixels: pixels,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 3,
  );

  const physics = SpotFeedScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  test(
    'coasts farther in either direction without boosting release velocity',
    () {
      for (final velocity in [-1800.0, 1800.0]) {
        final position = metrics(5000);
        final standard = const ClampingScrollPhysics()
            .createBallisticSimulation(position, velocity)!;
        final coast = physics
            .applyTo(const ClampingScrollPhysics())
            .createBallisticSimulation(position, velocity)!;
        expect(coast.dx(0), closeTo(standard.dx(0), .001));
        expect(
          (coast.x(10) - 5000).abs(),
          greaterThan((standard.x(10) - 5000).abs() * 1.4),
        );
        expect(coast.isDone(10), isTrue);
      }
    },
  );

  test('stops at edges and does not snap a resting offset', () {
    expect(physics.createBallisticSimulation(metrics(0), -1800), isNull);
    expect(physics.createBallisticSimulation(metrics(10000), 1800), isNull);
    expect(physics.createBallisticSimulation(metrics(123.4), 0), isNull);
    expect(physics.applyPhysicsToUserOffset(metrics(5000), 25), 25);
  });
}
