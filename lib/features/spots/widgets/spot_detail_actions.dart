import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/platform/external_links.dart'
    show launchExternalUrl;
import 'package:ccs_app/features/spots/navigation/waze_route.dart'
    show openWazeRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show toggleSpotLike, watchCurrentUserLikedSpot;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/core/platform/external_links.dart';
import 'package:ccs_app/core/platform/external_links.dart'
    show launchExternalUrl;
import 'package:ccs_app/core/platform/external_links.dart';

class SpotDetailEngagementPanel extends StatelessWidget {
  final CarSpot spot;

  const SpotDetailEngagementPanel({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: watchCurrentUserLikedSpot(spot),
      builder: (context, likedSnapshot) {
        final liked = likedSnapshot.data ?? false;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      color: spot.likeCount > 0
                          ? Colors.redAccent
                          : Colors.white38,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    CcsText(
                      '${spot.likeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    CcsText(
                      trText('Likes'),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: trText(liked ? 'Liked' : 'Like'),
                child: InkWell(
                  onTap: () => toggleSpotLike(context, spot, liked),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: liked
                          ? Colors.redAccent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: liked ? Colors.redAccent : Colors.white12,
                      ),
                    ),
                    child: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? Colors.redAccent : Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SpotRouteActions extends StatelessWidget {
  final CarSpot spot;
  final VoidCallback onShowMap;

  const SpotRouteActions({
    super.key,
    required this.spot,
    required this.onShowMap,
  });

  Widget actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final enabled = onTap != null;

    return Expanded(
      child: SizedBox(
        height: 52,
        child: filled
            ? ElevatedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 16),
                label: CcsText(
                  trText(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: enabled ? blue : Colors.white10,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 16),
                label: CcsText(
                  trText(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: enabled ? blue : Colors.white38,
                  side: BorderSide(color: enabled ? blue : Colors.white12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationAvailable =
        !spot.isTemporary || spot.isTemporaryLocationAvailableNow;
    final hasVideo = spot.reelLink.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              actionButton(
                icon: Icons.map_outlined,
                label: 'Map',
                onTap: locationAvailable ? onShowMap : null,
              ),
              const SizedBox(width: 8),
              actionButton(
                icon: Icons.navigation,
                label: 'Waze',
                filled: true,
                onTap: locationAvailable
                    ? () => openWazeRoute(context, spot)
                    : null,
              ),
              const SizedBox(width: 8),
              actionButton(
                icon: Icons.play_circle_outline,
                label: 'Video',
                onTap: hasVideo
                    ? () => launchExternalUrl(context, spot.reelLink)
                    : null,
              ),
            ],
          ),
          if (!locationAvailable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  color: Colors.orangeAccent,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CcsText(
                    trText('Location not available yet'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CcsText(
                  spot.temporaryLocationAvailableAtLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
