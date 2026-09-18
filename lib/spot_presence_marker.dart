import 'package:flutter/material.dart';

/// Anchor the bottom of the centered icon, not the label/presence hit box.
/// flutter_map uses the opposite alignment for the geographic anchor.
Alignment spotIconBottomAlignment(double markerHeight, double iconHeight) =>
    Alignment(0, -(iconHeight / markerHeight).clamp(0.0, 1.0));

/// Keeps the icon horizontally centered, with a separate people button.
class SpotPresenceMarker extends StatelessWidget {
  static const double sideSpace = 50;

  final Widget marker;
  final VoidCallback onSpotTap;
  final Widget? peopleButton;

  const SpotPresenceMarker({
    super.key,
    required this.marker,
    required this.onSpotTap,
    this.peopleButton,
  });

  @override
  Widget build(BuildContext context) {
    final spot = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSpotTap,
      child: marker,
    );
    if (peopleButton == null) return spot;

    // Reserve equal space on both sides so the map coordinate stays beneath
    // the original icon. The button stays inside the marker's hit-test bounds.
    return Stack(
      children: [
        Positioned.fill(
          left: sideSpace,
          right: sideSpace,
          child: spot,
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: sideSpace,
          child: Center(child: peopleButton),
        ),
      ],
    );
  }
}
