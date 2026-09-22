import 'package:ccs_app/features/map/widgets/map_profile_actions.dart'
    show MapPreviewProfileActions;
import 'package:ccs_app/features/spots/widgets/save_spot_button.dart'
    show SaveSpotButton;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/widgets/map_marker_badges.dart'
    show VerifiedSpotBadge;
import 'package:ccs_app/features/map/widgets/spot_presence_sheet.dart'
    show spotPeopleLabel;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;
import 'package:ccs_app/shared/widgets/user_avatar.dart' show UserAvatarCircle;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class SpotMapCard extends StatelessWidget {
  final CarSpot spot;
  final VoidCallback onOpen;
  final int peopleCount;
  final VoidCallback? onPeople;

  const SpotMapCard({
    super.key,
    required this.spot,
    required this.onOpen,
    this.peopleCount = 0,
    this.onPeople,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SpotPhoto(
              spot: spot,
              width: 96,
              height: 124,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CcsText(
                        spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (spot.verifiedOnly) ...[
                      const SizedBox(width: 8),
                      const VerifiedSpotBadge(size: 18),
                    ],
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    CcsText(
                      '${spot.likeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                CcsText(
                  spot.cityCountry,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (onPeople != null)
                  TextButton.icon(
                    onPressed: onPeople,
                    icon: const Icon(Icons.people_alt_outlined, size: 18),
                    label: CcsText(spotPeopleLabel(peopleCount)),
                  ),
                const SizedBox(height: 8),
                CcsText(
                  spot.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (spot.verifiedOnly)
                      SpotInfoTag(label: 'Verified only', icon: Icons.verified),
                    if (spot.isTemporary)
                      SpotInfoTag(
                        fullLabel: true,
                        label: spot.temporaryTimeLabel,
                        icon: Icons.event,
                      ),
                    if (spot.isTemporary &&
                        !spot.isTemporaryLocationAvailableNow)
                      SpotInfoTag(
                        fullLabel: true,
                        label: spot.temporaryLocationAvailableAtLabel,
                        icon: Icons.visibility_off_outlined,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          onPressed: onOpen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.open_in_full, size: 16),
                              SizedBox(width: 8),
                              CcsText('View Spot'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SaveSpotButton(spot: spot, compact: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LiveLocationMapCard extends StatelessWidget {
  final LiveLocationData location;
  final bool isFriend;
  final VoidCallback onOpen;
  final VoidCallback onRoute;

  const LiveLocationMapCard({
    super.key,
    required this.location,
    required this.isFriend,
    required this.onOpen,
    required this.onRoute,
  });

  FriendUserData get user {
    return FriendUserData(
      uid: location.uid,
      username: location.username,
      name: location.name,
      email: '',
      photoUrl: location.photoUrl,
      verified: location.verified,
      role: location.role,
      globalChatModerator: false,
      banned: false,
      deleted: false,
      isOnline: true,
      lastSeenAtMillis: location.updatedAtMillis,
      isSharingLiveLocation: true,
      liveLocationExpiresAtMillis: location.expiresAtMillis,
      liveLocationVisibleToUserIds: location.visibleToUserIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileUser = user;
    final updatedLabel = location.updatedAtMillis > 0
        ? 'Updated ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(location.updatedAtMillis))}'
        : 'Live location';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              UserAvatarCircle(user: profileUser, size: 84),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CcsText(
                            displayUsername(location.username),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        UserPrimaryBadge(
                          role: location.role,
                          verified: location.verified,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      updatedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        SpotInfoTag(
                          label: isFriend ? 'Friend' : 'Driver',
                          icon: isFriend ? Icons.people : Icons.person,
                        ),
                        SpotInfoTag(
                          label: location.isActive ? 'online' : 'offline',
                          icon: Icons.my_location,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MapPreviewProfileActions(onOpen: onOpen, onSecondary: onRoute),
        ],
      ),
    );
  }
}
