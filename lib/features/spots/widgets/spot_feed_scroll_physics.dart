import 'package:flutter/widgets.dart';

/// Longer free coasting, without changing finger tracking or snapping to cards.
class SpotFeedScrollPhysics extends ClampingScrollPhysics {
  const SpotFeedScrollPhysics({super.parent});

  @override
  SpotFeedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SpotFeedScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final simulation = super.createBallisticSimulation(position, velocity);
    // Preserve the standard edge recovery and stopped-scroll handling.
    if (simulation is! ClampingScrollSimulation) return simulation;
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.008,
      tolerance: toleranceFor(position),
    );
  }
}
