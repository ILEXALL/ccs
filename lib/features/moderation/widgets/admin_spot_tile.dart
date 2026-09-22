import 'package:ccs_app/features/moderation/widgets/admin_status_badge.dart'
    show AdminStatusBadge;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/moderation/screens/spot_review_screen.dart'
    show AdminSpotReviewScreen;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;

class AdminSpotTile extends StatelessWidget {
  final CarSpot spot;

  const AdminSpotTile({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(builder: (_) => AdminSpotReviewScreen(spot: spot)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SpotPhoto(
              spot: spot,
              width: 82,
              height: 82,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CcsText(
                    spot.cityCountry,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AdminStatusBadge(status: spot.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: spot.addedByUid.trim().isEmpty
                            ? CcsText(
                                'Added by ${spot.addedBy}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38),
                              )
                            : InkWell(
                                onTap: () => openUserProfile(
                                  context,
                                  uid: spot.addedByUid,
                                  fallbackUsername: spot.addedBy,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                child: CcsText(
                                  'Added by ${displayUsername(spot.addedBy)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: blue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
