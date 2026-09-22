import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, userPresenceDocument, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/data/direct_chats.dart'
    show createOrOpenDirectChat;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show localizedFriendActionError;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show lastOnlineLabelFromMillis, userAppearsOnlineFromPresence;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/models/public_profile.dart'
    show PublicUserProfileData;
import 'package:ccs_app/features/profile/widgets/garage_gallery.dart'
    show GarageCard;
import 'package:ccs_app/features/profile/widgets/profile_actions.dart'
    show PublicProfileActions, setProfileVerifiedStatus;
import 'package:ccs_app/features/profile/widgets/profile_footer.dart'
    show ProfileActionFooter;
import 'package:ccs_app/features/profile/widgets/profile_info.dart'
    show ProfileInfoRow;
import 'package:ccs_app/features/profile/widgets/profile_social_links.dart'
    show CompactSocialLinkButton;
import 'package:ccs_app/features/progression/screens/xp_history_screen.dart'
    show XpHistoryScreen;
import 'package:ccs_app/features/progression/widgets/featured_achievement.dart'
    show FeaturedProfileAchievement;
import 'package:ccs_app/features/progression/widgets/xp_summary.dart'
    show XpSummaryCard;
import 'package:ccs_app/features/spots/screens/creator_spots_screen.dart'
    show localizedProfileLocation, profileCountLabel;
import 'package:ccs_app/features/spots/widgets/creator_spots_badge.dart'
    show CreatorSpotsBadge;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class PublicUserProfileScreen extends StatelessWidget {
  final String userId;
  final String fallbackUsername;

  const PublicUserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackUsername = '',
  });

  Widget avatar(PublicUserProfileData profile) {
    Widget fallback() {
      final initial = profile.username.trim().isEmpty
          ? 'C'
          : profile.username.trim()[0].toUpperCase();

      return Center(
        child: CcsText(
          initial,
          style: const TextStyle(
            color: blue,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.5)),
      ),
      child: ClipOval(
        child: localFileExists(profile.avatarPath)
            ? Image.file(File(profile.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(profile.photoUrl)
            ? Image.network(
                profile.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }

  Widget profileHeader(BuildContext context, PublicUserProfileData profile) {
    final visibleGarageCount = profile.settings.showGarage
        ? profile.garage.length
        : 0;
    final garageValue = profileCountLabel(visibleGarageCount);
    final socialButtons = <Widget>[
      if (profile.settings.instagram.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.camera_alt,
          label: 'Instagram',
          value: profile.settings.instagram,
        ),
      if (profile.settings.tiktok.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.music_note,
          label: 'TikTok',
          value: profile.settings.tiktok,
        ),
      if (profile.settings.telegram.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.send,
          label: 'Telegram',
          value: profile.settings.telegram,
        ),
    ];
    final showActions = profile.uid != currentUser.uid;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: FittedBox(child: avatar(profile)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CcsText(
                            profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (showActions) ...[
                          const SizedBox(width: 8),
                          PublicProfileActions(profile: profile),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        UserPrimaryBadge(
                          role: profile.role,
                          verified: profile.verified,
                          globalChatModerator: profile.globalChatModerator,
                          showLabel: true,
                          compact: true,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: profile.appearsOnline
                                    ? Colors.greenAccent
                                    : Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            CcsText(
                              trText(
                                profile.appearsOnline ? 'online' : 'offline',
                              ),
                              style: TextStyle(
                                color: profile.appearsOnline
                                    ? Colors.greenAccent
                                    : Colors.white54,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    CcsText(
                      lastOnlineLabelFromMillis(profile.lastSeenAtMillis),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              FeaturedProfileAchievement(userId: profile.uid, emblemSize: 56),
            ],
          ),
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            CcsText(
              profile.bio,
              style: const TextStyle(color: Colors.white60, height: 1.25),
            ),
          ],
          const SizedBox(height: 9),
          ProfileInfoRow(
            location: localizedProfileLocation(profile.city, profile.country),
            cars: garageValue,
            spots: CreatorSpotsBadge(
              uid: profile.uid,
              username: profile.username,
            ),
          ),
          if (showActions || socialButtons.isNotEmpty) ...[
            const SizedBox(height: 14),
            ProfileActionFooter(
              action: showActions ? messageButton(context, profile) : null,
              links: socialButtons,
            ),
          ],
        ],
      ),
    );
  }

  Widget messageButton(BuildContext context, PublicUserProfileData profile) {
    if (profile.uid == currentUser.uid) {
      return const SizedBox.shrink();
    }

    final user = FriendUserData(
      uid: profile.uid,
      username: profile.username,
      name: profile.name,
      email: profile.email,
      photoUrl: profile.photoUrl,
      avatarPath: profile.avatarPath,
      verified: profile.verified,
      role: profile.role,
      globalChatModerator: profile.globalChatModerator,
      banned: false,
      deleted: false,
    );

    return SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton.icon(
        onPressed: () async {
          try {
            final chatId = await createOrOpenDirectChat(user);
            final chat = ChatThreadData(
              id: chatId,
              isGroup: false,
              name: '',
              photoUrl: '',
              memberIds: [currentUser.uid, user.uid],
              memberUsernames: [currentUser.username, user.username],
              memberPhotoUrls: [
                currentUser.photoUrl ?? '',
                user.photoUrl ?? '',
              ],
              lastMessage: '',
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            );

            if (!context.mounted) {
              return;
            }

            Navigator.push(
              context,
              appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
            );
          } catch (error) {
            if (!context.mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: CcsText(
                  localizedFriendActionError(error, 'Could not open chat.'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: CcsText(trText('Message')),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget socialLinks(PublicUserProfileData profile) {
    final settings = profile.settings;
    final links = <Widget>[
      if (settings.instagram.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.camera_alt,
          label: 'Instagram',
          value: settings.instagram,
        ),
      if (settings.tiktok.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.music_note,
          label: 'TikTok',
          value: settings.tiktok,
        ),
      if (settings.telegram.trim().isNotEmpty)
        CompactSocialLinkButton(
          icon: Icons.send,
          label: 'Telegram',
          value: settings.telegram,
        ),
    ];

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
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
            'Social links',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: links),
        ],
      ),
    );
  }

  Widget blockedProfileBody(
    BuildContext context,
    PublicUserProfileData profile,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              avatar(profile),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: UserPrimaryBadge(
                        role: profile.role,
                        verified: profile.verified,
                        globalChatModerator: profile.globalChatModerator,
                        showLabel: true,
                        compact: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CcsText(
                      trText('This profile is not available.'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      trText('Only avatar and nickname are visible.'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget profileBody(BuildContext context, PublicUserProfileData profile) {
    final visibleGarage = profile.settings.showGarage
        ? profile.garage
        : const <GarageCar>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
      children: [
        profileHeader(context, profile),
        ...[
          const SizedBox(height: 12),
          XpSummaryCard(
            userId: profile.uid,
            onTap: () {
              Navigator.push(
                context,
                appPageRoute(
                  builder: (_) => XpHistoryScreen(userId: profile.uid),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        if (userRoleIsStaff(currentUser.role) &&
            profile.uid != currentUser.uid &&
            profile.role == UserRole.user) ...[
          Container(
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: profile.verified
                    ? blue.withValues(alpha: 0.55)
                    : Colors.white12,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile.adaptive(
                value: profile.verified,
                activeThumbColor: blue,
                secondary: Icon(
                  profile.verified
                      ? Icons.verified_rounded
                      : Icons.verified_outlined,
                  color: profile.verified ? blue : Colors.white54,
                ),
                title: CcsText(
                  profile.verified ? 'Verified user' : 'User not verified',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: const CcsText(
                  'Allow this user to create and see verified-only spots.',
                  style: TextStyle(color: Colors.white54),
                ),
                onChanged: (value) =>
                    setProfileVerifiedStatus(context, profile, value),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (visibleGarage.isEmpty)
          const EmptyStateCard(
            icon: Icons.directions_car,
            title: 'No garage shared',
            text: 'This driver has not shared car builds yet.',
          )
        else
          for (final car in visibleGarage) ...[
            GarageCard(car: car),
            const SizedBox(height: 16),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsAppBarLogo(),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: ccsAppBarActions(),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: usersCollection()
            .doc(userId)
            .debugSnapshots('profile: public user profile listener'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final doc = snapshot.data;

          if (doc == null || !doc.exists) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile not found',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          final profile = PublicUserProfileData.fromFirestore(doc);

          if (profile.deleted) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.person_off,
                title: 'Profile deleted',
                text: 'This user profile is not available anymore.',
              ),
            );
          }

          if (profile.currentViewerIsBlocked &&
              !userRoleIsStaff(currentUser.role)) {
            return blockedProfileBody(context, profile);
          }

          if (!profile.canCurrentUserView) {
            return Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  const EmptyStateCard(
                    icon: Icons.lock,
                    title: 'Private profile',
                    text: 'This driver keeps their profile private.',
                  ),
                  const SizedBox(height: 12),
                  CreatorSpotsBadge(
                    uid: profile.uid,
                    username: profile.username,
                  ),
                ],
              ),
            );
          }

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userPresenceDocument(
              userId,
            ).debugSnapshots('profile: public user presence listener'),
            builder: (context, presenceSnapshot) {
              final presenceData = presenceSnapshot.data?.data();
              final presenceLastSeenAtMillis = presenceData == null
                  ? 0
                  : timestampMillisFromFirebase(presenceData['lastSeenAt']);
              final profileLastSeenAtMillis = profile.lastSeenAtMillis;
              final mergedLastSeenAtMillis =
                  presenceLastSeenAtMillis > profileLastSeenAtMillis
                  ? presenceLastSeenAtMillis
                  : profileLastSeenAtMillis;
              final presenceAppearsOnline =
                  presenceData != null &&
                  userAppearsOnlineFromPresence(
                    isOnline: presenceData['isOnline'] == true,
                    lastSeenAtMillis: presenceLastSeenAtMillis,
                    isSharingLiveLocation: false,
                    liveLocationExpiresAtMillis: null,
                  );
              final profileWithPresence = presenceData == null
                  ? profile
                  : profile.copyWith(
                      isOnline: presenceAppearsOnline || profile.appearsOnline,
                      lastSeenAtMillis: mergedLastSeenAtMillis,
                    );

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: liveLocationsCollection()
                    .doc(userId)
                    .debugSnapshots('profile: public live location listener'),
                builder: (context, liveSnapshot) {
                  var isSharingLiveLocation = false;
                  final liveDoc = liveSnapshot.data;

                  int? liveLocationExpiresAtMillis;
                  if (liveDoc != null && liveDoc.exists) {
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    final liveLocation = LiveLocationData.fromFirestore(
                      liveDoc,
                    );
                    final currentUserCanView =
                        currentUid != null &&
                        (liveLocation.uid == currentUid ||
                            liveLocation.visibleToUserIds.contains(currentUid));
                    isSharingLiveLocation =
                        currentUserCanView && liveLocation.isActive;
                    liveLocationExpiresAtMillis = isSharingLiveLocation
                        ? liveLocation.expiresAtMillis
                        : null;
                  }

                  return profileBody(
                    context,
                    profileWithPresence.copyWith(
                      isSharingLiveLocation: isSharingLiveLocation,
                      liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// One live directory subscription while the Friends screen is open, rather
// than downloading the first 50 profiles on every keystroke. No usernameKey
// ordering: legacy accounts without that field must remain searchable.
// Match only the @token at the caret, never an email address or selected text.
