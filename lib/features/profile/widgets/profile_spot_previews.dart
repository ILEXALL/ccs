import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/map/widgets/map_marker_badges.dart'
    show VerifiedSpotBadge;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/features/spots/screens/add_spot_screen.dart'
    show PendingBadge;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/screens/submissions_screen.dart'
    show SavedScreen, UserSubmissionsScreen;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;

class ProfileSubmissionsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const ProfileSubmissionsPreview({super.key, required this.spots});

  @override
  Widget build(BuildContext context) {
    final latest = spots.isEmpty ? null : spots.first;
    final pendingCount = spots
        .where((spot) => spot.status == SpotStatus.pending)
        .length;
    final liveCount = spots
        .where((spot) => spot.status == SpotStatus.approved)
        .length;
    final rejectedCount = spots
        .where((spot) => spot.status == SpotStatus.rejected)
        .length;
    final summary = spots.isEmpty
        ? 'No spots created yet.'
        : [
            if (pendingCount > 0) '$pendingCount pending review',
            if (liveCount > 0) '$liveCount live',
            if (rejectedCount > 0) '$rejectedCount rejected',
          ].join(' • ');

    return InkWell(
      onTap: spots.isEmpty
          ? null
          : () {
              Navigator.push(
                context,
                appPageRoute(builder: (_) => const UserSubmissionsScreen()),
              );
            },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CcsText(
              'Submissions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            CcsText(summary, style: const TextStyle(color: Colors.white54)),
            if (latest != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  SpotPhoto(
                    spot: latest,
                    width: 64,
                    height: 64,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CcsText(
                          latest.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        CcsText(
                          latest.cityCountry,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 8),
                        PendingBadge(status: latest.status),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileSavedSpotsPreview extends StatelessWidget {
  final List<CarSpot> spots;

  const ProfileSavedSpotsPreview({super.key, required this.spots});

  @override
  Widget build(BuildContext context) {
    final visibleSpots = spots.take(3).toList();
    final hiddenCount = spots.length - visibleSpots.length;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => const SavedScreen()),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: CcsText(
                    'Saved Spots',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                CcsText(
                  '${spots.length}',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
            const SizedBox(height: 8),
            CcsText(
              spots.isEmpty
                  ? 'Saved spots will appear here.'
                  : hiddenCount > 0
                  ? 'Your bookmarked car spots. Tap to view all $hiddenCount more.'
                  : 'Your bookmarked car spots. Tap to view all.',
              style: const TextStyle(color: Colors.white54),
            ),
            if (visibleSpots.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final spot in visibleSpots) ...[
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => SpotDetailScreen(spot: spot),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SpotPhoto(
                          spot: spot,
                          width: 54,
                          height: 54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (spot.verifiedOnly) ...[
                                    const SizedBox(width: 5),
                                    const VerifiedSpotBadge(size: 14),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              CcsText(
                                spot.cityCountry,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
                if (spot != visibleSpots.last)
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
