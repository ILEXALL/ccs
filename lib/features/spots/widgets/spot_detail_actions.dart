import 'package:ccs_app/shared/media/event_video_screen.dart'
    show openEventVideo;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/spots/navigation/waze_route.dart'
    show openWazeRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show toggleSpotLike, watchCurrentUserLikedSpot;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

class SpotDetailEngagementPanel extends StatelessWidget {
  final CarSpot spot;

  const SpotDetailEngagementPanel({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: watchCurrentUserLikedSpot(spot),
      builder: (context, likedSnapshot) {
        final liked = likedSnapshot.data ?? false;

        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => toggleSpotLike(context, spot, liked),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFCED7E5),
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
              minimumSize: const Size(48, 48),
            ),
            icon: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 21,
              color: liked ? Colors.redAccent : const Color(0xFF91A0B5),
            ),
            label: CcsText(
              '${spot.likeCount} ${trText('Likes')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );
  }
}

class SpotRouteActions extends StatelessWidget {
  final CarSpot spot;
  final VoidCallback onShowMap;
  final bool showVideo;

  const SpotRouteActions({
    super.key,
    required this.spot,
    required this.onShowMap,
    this.showVideo = true,
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
                  foregroundColor: enabled
                      ? const Color(0xFFD8E6FF)
                      : Colors.white38,
                  side: BorderSide(
                    color: enabled ? const Color(0xFF47628C) : Colors.white12,
                  ),
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
    final hasVideo = showVideo && spot.reelLink.trim().isNotEmpty;

    if (spot.isTemporary && !locationAvailable) {
      return hasVideo
          ? Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => openEventVideo(context, spot.reelLink),
                icon: const Icon(Icons.play_circle_outline),
                label: const CcsText('Video'),
              ),
            )
          : const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: spot.isTemporary ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: spot.isTemporary
          ? BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            )
          : null,
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
              if (hasVideo) const SizedBox(width: 8),
              if (hasVideo)
                actionButton(
                  icon: Icons.play_circle_outline,
                  label: 'Video',
                  onTap: hasVideo
                      ? () => openEventVideo(context, spot.reelLink)
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
