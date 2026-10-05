import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/map/widgets/map_marker_badges.dart'
    show VerifiedSpotBadge;
import 'package:ccs_app/features/map/screens/globe_map_screen.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;

class AdminSpotLocationReviewMapScreen extends StatefulWidget {
  final CarSpot spot;

  const AdminSpotLocationReviewMapScreen({super.key, required this.spot});

  @override
  State<AdminSpotLocationReviewMapScreen> createState() =>
      _AdminSpotLocationReviewMapScreenState();
}

class _AdminSpotLocationReviewMapScreenState
    extends State<AdminSpotLocationReviewMapScreen> {
  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            GlobeMapScreen(
              showControls: false,
              isSharing: false,
              sharingBusy: false,
              onShareChanged: (_) async {},
              onFilter: () async {},
              onAddReport: () async {},
              onLocate: () async {},
              cardBuilder: (_, _, _) => null,
              readFeatures: () => {
                'type': 'FeatureCollection',
                'camera': {
                  'revision': 0,
                  'center': [
                    spot.coordinates.longitude,
                    spot.coordinates.latitude,
                  ],
                  'zoom': 17,
                },
                'features': [
                  {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [
                        spot.coordinates.longitude,
                        spot.coordinates.latitude,
                      ],
                    },
                    'properties': {
                      'kind': 'pin',
                      'icon': 'ccs-pin-red',
                      'label': spot.name,
                      'color': '#ff5252',
                    },
                  },
                ],
              },
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Material(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(16),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: blue),
                        tooltip: 'Back to review',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: panelGlass,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const CcsText(
                          'Review submitted pin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: panelGlass,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.7),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SpotPhoto(
                        spot: spot,
                        width: 96,
                        height: 86,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: CcsText(
                                  spot.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (spot.verifiedOnly) ...[
                                const SizedBox(width: 7),
                                const VerifiedSpotBadge(size: 18),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          CcsText(
                            spot.cityCountry,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 8),
                          CcsText(
                            'Lat ${spot.coordinates.latitude.toStringAsFixed(6)} • Lng ${spot.coordinates.longitude.toStringAsFixed(6)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
