import 'package:flutter/material.dart';

/// Keeps the icon horizontally centred within the marker, with a separate
/// people button. The map marker alignment positions the visible pin tip.
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
        Positioned.fill(left: sideSpace, right: sideSpace, child: spot),
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

// Visible pin tips measured within each square asset (including its transparent
// padding and category text). Keep these in sync when replacing icon artwork.
const spotIconTipFractions = <String, Offset>{
  'activity.png': Offset(0.5013, 0.7513),
  'activity_light.png': Offset(0.5013, 0.7513),
  'detailing.png': Offset(0.4987, 0.75391),
  'detailing_light.png': Offset(0.4987, 0.75391),
  'drag.png': Offset(0.5013, 0.74609),
  'drag_light.png': Offset(0.5013, 0.74609),
  'drift.png': Offset(0.5, 0.71745),
  'drift_light.png': Offset(0.5, 0.71745),
  'drive.png': Offset(0.5, 0.69661),
  'drive_light.png': Offset(0.5, 0.69661),
  'food.png': Offset(0.5013, 0.74609),
  'food_light.png': Offset(0.5013, 0.74609),
  'meet.png': Offset(0.4987, 0.72526),
  'meet_light.png': Offset(0.4987, 0.72526),
  'offroad.png': Offset(0.4987, 0.77474),
  'offroad_light.png': Offset(0.49963, 0.77474),
  'photo.png': Offset(0.49948, 0.73568),
  'photo_light.png': Offset(0.4987, 0.73568),
  'scrap.png': Offset(0.4987, 0.72266),
  'scrap_light.png': Offset(0.4987, 0.72266),
  'service.png': Offset(0.5, 0.69141),
  'service_light.png': Offset(0.5, 0.69401),
  'store.png': Offset(0.5, 0.73568),
  'store_2.png': Offset(0.5, 0.73568),
  'store_light.png': Offset(0.5, 0.73568),
  'store_light_2.png': Offset(0.5, 0.73568),
  'track.png': Offset(0.5013, 0.74089),
  'track_light.png': Offset(0.5013, 0.74089),
  'wash.png': Offset(0.5013, 0.80078),
  'wash_light.png': Offset(0.5013, 0.80078),
};

Alignment spotIconTipAlignment({
  required String asset,
  required double iconSize,
  required double markerWidth,
  required double markerHeight,
}) {
  final tip =
      spotIconTipFractions[asset.split('/').last] ?? const Offset(0.5, 1);
  // The icon is centred inside a larger hit target. flutter_map aligns the
  // marker relative to the coordinate, so the alignment is the inverse of
  // the desired anchor. This also keeps rotation centred on the pin tip.
  return Alignment(
    -2 * (tip.dx - 0.5) * iconSize / markerWidth,
    -2 * (tip.dy - 0.5) * iconSize / markerHeight,
  );
}
