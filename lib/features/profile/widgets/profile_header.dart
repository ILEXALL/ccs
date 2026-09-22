import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/profile/models/user_profile.dart'
    show UserProfileData;
import 'package:ccs_app/features/profile/widgets/profile_info.dart'
    show ProfileInfoRow;
import 'package:ccs_app/features/profile/widgets/profile_social_links.dart'
    show CompactProfileSocialLinks;
import 'package:ccs_app/features/progression/widgets/featured_achievement.dart'
    show FeaturedProfileAchievement;
import 'package:ccs_app/features/spots/screens/creator_spots_screen.dart'
    show localizedProfileLocation;
import 'package:ccs_app/features/spots/widgets/creator_spots_badge.dart'
    show CreatorSpotsBadge;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class ProfileHeader extends StatelessWidget {
  final UserProfileData profile;
  final String garageValue;
  final String spotsValue;
  final VoidCallback onEdit;

  const ProfileHeader({
    super.key,
    required this.profile,
    required this.garageValue,
    required this.spotsValue,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: blue.withValues(alpha: 0.5)),
                ),
                child: ClipOval(
                  child: localFileExists(profile.avatarPath)
                      ? Image.file(
                          File(profile.avatarPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: CcsText(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : isNetworkUrl(profile.photoUrl)
                      ? Image.network(
                          profile.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) {
                            return const Center(
                              child: CcsText(
                                'CCS',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: CcsText(
                            'CCS',
                            style: TextStyle(
                              color: blue,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CcsText(
                            profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: UserPrimaryBadge(
                        role: currentUser.role,
                        verified: currentUser.verified,
                        globalChatModerator: currentUser.globalChatModerator,
                        showLabel: true,
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      profile.bio,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              FeaturedProfileAchievement(userId: currentUser.uid),
            ],
          ),
          const SizedBox(height: 8),
          ProfileInfoRow(
            location: localizedProfileLocation(profile.city, profile.country),
            cars: garageValue,
            spots: CreatorSpotsBadge(
              uid: currentUser.uid,
              username: profile.username,
            ),
          ),
          const SizedBox(height: 14),
          CompactProfileSocialLinks(
            action: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 16),
                label: const CcsText('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
