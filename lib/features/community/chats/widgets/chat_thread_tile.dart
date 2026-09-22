import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show currentUserCanDeleteGroupChat;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show chatRemovalButtonLabel;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show confirmAndRemoveChat;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userPresenceDocument, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserHomeCountryCode, currentUserProfileRevision;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/community/data/community_country.dart'
    show profileAuthorCountryCode;
import 'package:ccs_app/features/community/groups/data/group_repository.dart'
    show groupMemberCountLabel, groupVisibilityLabel;
import 'package:ccs_app/features/community/widgets/country_selector.dart'
    show CommunityAvatarWithCountryFlag;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/features/notifications/models/badge_label.dart'
    show compactBadgeLabel;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show markChatNotificationsRead;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show
        OnlineStatusBadge,
        UserAvatarCircle,
        UserAvatarFallback,
        fallbackChatMember,
        friendUserFromSnapshot;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class GlobalSmallAvatar extends StatelessWidget {
  final String avatarUrl;
  final String username;
  final double size;

  const GlobalSmallAvatar({
    super.key,
    required this.avatarUrl,
    required this.username,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final letter = username.trim().isEmpty
        ? '?'
        : username.trim().substring(0, 1).toUpperCase();

    if (isNetworkUrl(avatarUrl)) {
      return ClipOval(
        child: Image.network(
          avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              UserAvatarFallback(size: size, icon: Icons.person),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Center(
        child: CcsText(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class LiveCommunityAuthorIdentity extends StatefulWidget {
  final String uid;
  final String fallbackAvatarUrl;
  final String fallbackUsername;
  final UserRole fallbackRole;
  final bool fallbackVerified;
  final bool fallbackGlobalChatModerator;
  final String authorCountryCode;
  final String channelCountryCode;

  const LiveCommunityAuthorIdentity({
    super.key,
    required this.uid,
    required this.fallbackAvatarUrl,
    required this.fallbackUsername,
    required this.fallbackRole,
    required this.fallbackVerified,
    required this.fallbackGlobalChatModerator,
    required this.authorCountryCode,
    required this.channelCountryCode,
  });

  @override
  State<LiveCommunityAuthorIdentity> createState() =>
      _LiveCommunityAuthorIdentityState();
}

class _LiveCommunityAuthorIdentityState
    extends State<LiveCommunityAuthorIdentity> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? profileStream;

  @override
  void initState() {
    super.initState();
    _updateProfileStream();
  }

  @override
  void didUpdateWidget(covariant LiveCommunityAuthorIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid.trim() != widget.uid.trim()) {
      _updateProfileStream();
    }
  }

  void _updateProfileStream() {
    final cleanUid = widget.uid.trim();
    profileStream = cleanUid.isEmpty || cleanUid == currentUser.uid
        ? null
        : usersCollection()
              .doc(cleanUid)
              .debugSnapshots('global chat: author profile listener');
  }

  Widget buildIdentity(Map<String, dynamic>? data) {
    final isCurrentUser = widget.uid.trim() == currentUser.uid;
    final username = isCurrentUser
        ? currentUser.username
        : stringFromFirebase(data?['username'], widget.fallbackUsername);
    final avatarUrl = isCurrentUser
        ? currentUser.photoUrl ?? widget.fallbackAvatarUrl
        : stringFromFirebase(data?['photoUrl'], widget.fallbackAvatarUrl);
    final role = isCurrentUser
        ? currentUser.role
        : data == null
        ? widget.fallbackRole
        : roleFromFirebase(data['role']);
    final verified = isCurrentUser
        ? currentUser.verified
        : data == null
        ? widget.fallbackVerified
        : userRoleIsStaff(role) || data['verified'] == true;
    final globalModerator = isCurrentUser
        ? currentUser.globalChatModerator
        : data == null
        ? widget.fallbackGlobalChatModerator
        : userDataHasCommunityModerationAccess(data);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CommunityAvatarWithCountryFlag(
          authorCountryCode: isCurrentUser
              ? currentUserHomeCountryCode()
              : profileAuthorCountryCode(data, widget.authorCountryCode),
          channelCountryCode: widget.channelCountryCode,
          avatar: GlobalSmallAvatar(
            avatarUrl: avatarUrl,
            username: username.trim().isEmpty
                ? widget.fallbackUsername
                : username,
            size: 34,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: CcsText(
                  displayUsername(
                    username.trim().isEmpty
                        ? widget.fallbackUsername
                        : username,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              UserPrimaryBadge(
                role: role,
                verified: verified,
                globalChatModerator: globalModerator,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = profileStream;
    if (stream == null) {
      return ValueListenableBuilder<int>(
        valueListenable: currentUserProfileRevision,
        builder: (context, _, child) => buildIdentity(null),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) => buildIdentity(snapshot.data?.data()),
    );
  }
}

class LiveUserSmallAvatar extends StatelessWidget {
  final String uid;
  final String fallbackAvatarUrl;
  final String fallbackUsername;
  final double size;

  const LiveUserSmallAvatar({
    super.key,
    required this.uid,
    required this.fallbackAvatarUrl,
    required this.fallbackUsername,
    this.size = 34,
  });

  Widget avatarFromData(Map<String, dynamic>? data) {
    final cleanUsername = stringFromFirebase(
      data?['username'],
      fallbackUsername,
    );
    final cleanAvatarUrl = stringFromFirebase(
      data?['photoUrl'],
      fallbackAvatarUrl,
    );

    return GlobalSmallAvatar(
      avatarUrl: cleanAvatarUrl,
      username: cleanUsername.trim().isEmpty ? fallbackUsername : cleanUsername,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return avatarFromData(null);
    }

    if (cleanUid == currentUser.uid) {
      return GlobalSmallAvatar(
        avatarUrl: currentUser.photoUrl ?? fallbackAvatarUrl,
        username: currentUser.username.trim().isEmpty
            ? fallbackUsername
            : currentUser.username,
        size: size,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCollection()
          .doc(cleanUid)
          .debugSnapshots('global chat: author avatar listener'),
      builder: (context, snapshot) {
        return avatarFromData(snapshot.data?.data());
      },
    );
  }
}

class SegmentBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const SegmentBadgeIcon({super.key, required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: Colors.redAccent,
      label: CcsText(compactBadgeLabel(count)),
      child: Icon(icon, size: 21),
    );
  }
}

class ChatThreadTile extends StatefulWidget {
  final ChatThreadData chat;
  final String currentUid;
  final int unreadCount;

  const ChatThreadTile({
    super.key,
    required this.chat,
    required this.currentUid,
    this.unreadCount = 0,
  });

  @override
  State<ChatThreadTile> createState() => _ChatThreadTileState();
}

class _ChatThreadTileState extends State<ChatThreadTile> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _directUserProfileStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _directUserPresenceStream;
  String? _directUserUid;

  ChatThreadData get chat => widget.chat;
  String get currentUid => widget.currentUid;
  int get unreadCount => widget.unreadCount;

  void _ensureDirectUserStreams(String uid) {
    if (_directUserUid == uid &&
        _directUserProfileStream != null &&
        _directUserPresenceStream != null) {
      return;
    }

    _directUserUid = uid;
    _directUserProfileStream = usersCollection()
        .doc(uid)
        .debugSnapshots('chat: list direct user profile listener');
    _directUserPresenceStream = userPresenceDocument(
      uid,
    ).debugSnapshots('chat: list direct user presence listener');
  }

  @override
  void didUpdateWidget(covariant ChatThreadTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextUid = otherUserId();
    if (nextUid != _directUserUid) {
      _directUserUid = null;
      _directUserProfileStream = null;
      _directUserPresenceStream = null;
    }
  }

  String? otherUserId() {
    if (chat.isGroup) {
      return null;
    }

    for (final uid in chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  Widget avatar(FriendUserData? directUser) {
    if (chat.isGroup) {
      final photoUrl = chat.photoUrl.trim();
      if (isNetworkUrl(photoUrl)) {
        return ClipOval(
          child: Image.network(
            photoUrl,
            width: 46,
            height: 46,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const UserAvatarFallback(size: 46, icon: Icons.groups),
          ),
        );
      }

      return const UserAvatarFallback(size: 46, icon: Icons.groups);
    }

    if (directUser != null) {
      return UserAvatarCircle(user: directUser, size: 46);
    }

    return const UserAvatarFallback(size: 46, icon: Icons.person_outline);
  }

  Widget subtitleLine(String subtitle, FriendUserData? directUser) {
    final unread = unreadCount > 0;
    final textStyle = TextStyle(
      color: unread ? Colors.white70 : Colors.white54,
      fontWeight: unread ? FontWeight.w800 : FontWeight.w400,
    );

    if (!chat.isGroup) {
      return Row(
        children: [
          OnlineStatusBadge(online: directUser?.appearsOnline ?? false),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: CcsText(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ],
        ],
      );
    }

    return CcsText(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );
  }

  Widget tile(BuildContext context, FriendUserData? directUser) {
    final title = !chat.isGroup && directUser != null
        ? displayUsername(directUser.username)
        : '${chat.isPrivate ? '🔒 ' : ''}${chat.titleForCurrentUser(currentUid)}';
    final subtitle = chat.subtitleForCurrentUser(currentUid);

    return InkWell(
      onTap: () {
        unawaited(markChatNotificationsRead(chat.id));
        Navigator.push(
          context,
          appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            avatar(directUser),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: CcsText(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (!chat.isGroup && directUser != null) ...[
                        const SizedBox(width: 4),
                        UserPrimaryBadge(
                          role: directUser.role,
                          verified: directUser.verified,
                          globalChatModerator: directUser.globalChatModerator,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  subtitleLine(subtitle, directUser),
                  if (chat.isGroup)
                    CcsText(
                      groupVisibilityLabel(chat.isPrivate) +
                          ' · ' +
                          groupMemberCountLabel(chat.memberIds.length),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: CcsText(
                  compactBadgeLabel(unreadCount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
            PopupMenuButton<String>(
              color: panel,
              icon: const Icon(Icons.more_horiz, color: Colors.white54),
              onSelected: (value) async {
                if (value == 'remove_chat') {
                  await confirmAndRemoveChat(context, chat);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'remove_chat',
                  child: Row(
                    children: [
                      Icon(
                        chat.isGroup
                            ? (currentUserCanDeleteGroupChat(chat)
                                  ? Icons.delete_outline
                                  : Icons.logout)
                            : Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      CcsText(
                        chatRemovalButtonLabel(chat),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
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
  Widget build(BuildContext context) {
    if (chat.isGroup) {
      return tile(context, null);
    }

    final uid = otherUserId();
    if (uid == null) {
      return tile(context, null);
    }

    final fallbackUser = fallbackChatMember(chat, uid);

    _ensureDirectUserStreams(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _directUserProfileStream,
      builder: (context, snapshot) {
        final directUser =
            friendUserFromSnapshot(snapshot.data) ?? fallbackUser;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _directUserPresenceStream,
          builder: (context, presenceSnapshot) {
            return tile(
              context,
              directUser.withPresenceFromMap(presenceSnapshot.data?.data()),
            );
          },
        );
      },
    );
  }
}
