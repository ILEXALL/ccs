import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show
        OnlineStatusBadge,
        UserAvatarCircle,
        UserAvatarFallback,
        fallbackChatMember,
        loadChatMembers;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;
import 'package:ccs_app/features/community/groups/controllers/group_settings_view_state.dart';

/// Renders reusable sections for GroupSettingsScreen.
class GroupSettingsContent implements GroupSettingsContentActions {
  final GroupSettingsViewState host;
  GroupSettingsContent(this.host);

  @override
  Widget avatarPreview() {
    if (isNetworkUrl(host.photoUrl)) {
      return ClipOval(
        child: Image.network(
          host.photoUrl,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const UserAvatarFallback(size: 96, icon: Icons.groups),
        ),
      );
    }

    return const UserAvatarFallback(size: 96, icon: Icons.groups);
  }

  @override
  Widget memberTile(FriendUserData user) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final isOwner = user.uid == host.ownerUid;
    final isModerator = host.moderatorIds.contains(user.uid);
    final canToggleModerator =
        host.controller.isCurrentUserGroupOwner &&
        user.uid != currentUser.uid &&
        !isOwner;
    final canRemove = host.controller.canRemoveGroupMember(user);

    return InkWell(
      onTap: () => openUserProfile(
        viewContext,
        uid: user.uid,
        fallbackUsername: user.username,
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            UserAvatarCircle(user: user, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: CcsText(
                          displayUsername(user.username),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (user.uid == currentUser.uid) ...[
                        const SizedBox(width: 6),
                        const CcsText(
                          'you',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      UserPrimaryBadge(
                        role: user.role,
                        verified: user.verified,
                        globalChatModerator: user.globalChatModerator,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      OnlineStatusBadge(online: user.appearsOnline),
                      if (isOwner)
                        SpotInfoTag(label: trText('owner'), icon: Icons.shield)
                      else if (isModerator)
                        SpotInfoTag(
                          label: trText('moderator'),
                          icon: Icons.admin_panel_settings,
                        )
                      else
                        SpotInfoTag(
                          label: trText('member'),
                          icon: Icons.person_outline,
                          color: const Color(0xFF94A3B8),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (canToggleModerator || canRemove)
              PopupMenuButton<String>(
                color: panel,
                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                onSelected: (value) {
                  if (value == 'toggle_moderator') {
                    unawaited(host.controller.toggleGroupModerator(user));
                  } else if (value == 'ban_member') {
                    unawaited(host.controller.permanentlyDenyGroupMember(user));
                  } else if (value == 'remove_member') {
                    unawaited(host.controller.removeGroupMember(user));
                  }
                },
                itemBuilder: (_) => [
                  if (currentUser.uid == host.ownerUid && canRemove)
                    PopupMenuItem(
                      value: 'ban_member',
                      child: CcsText(
                        communityText(
                          en: 'Permanently deny access',
                          ru: 'Запретить доступ навсегда',
                          lv: 'Neatgriezeniski liegt piekļuvi',
                        ),
                      ),
                    ),
                  if (canToggleModerator)
                    PopupMenuItem(
                      value: 'toggle_moderator',
                      child: CcsText(
                        trText(
                          isModerator
                              ? 'Remove group moderator'
                              : 'Make group moderator',
                        ),
                      ),
                    ),
                  if (canRemove)
                    PopupMenuItem(
                      value: 'remove_member',
                      child: CcsText(
                        trText('Remove from group'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget membersSection() {
    return FutureBuilder<List<FriendUserData>>(
      future: loadChatMembers(host.controller.localChatData),
      builder: (context, snapshot) {
        final chatData = host.controller.localChatData;
        final members =
            snapshot.data ??
            [
              for (final uid in host.memberIds)
                fallbackChatMember(chatData, uid),
            ];
        final visibleMembers = host.controller.canManageGroupMembers
            ? members
            : members.where((member) => member.uid == currentUser.uid).toList();

        return Container(
          padding: const EdgeInsets.all(14),
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
                  Expanded(
                    child: CcsText(
                      host.controller.canManageGroupMembers
                          ? trText('Members')
                          : trText('Your role'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (host.controller.canManageGroupMembers)
                    IconButton(
                      tooltip: 'Add members',
                      onPressed: host.isSaving
                          ? null
                          : host.controller.addMembersToGroup,
                      icon: const Icon(Icons.person_add_alt_1, color: blue),
                    ),
                  if (host.controller.canManageGroupMembers)
                    CcsText(
                      '${members.length}',
                      style: const TextStyle(
                        color: blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final member in visibleMembers) memberTile(member),
            ],
          ),
        );
      },
    );
  }
}
