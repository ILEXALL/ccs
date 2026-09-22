import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/friends/data/blocked_users.dart'
    show loadCurrentBlockedUsers, unblockUserById;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show localizedFriendActionError;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen>
    with LanguageReactiveState {
  late Future<List<FriendUserData>> blockedUsersFuture;
  final Set<String> busyUserIds = <String>{};

  @override
  void initState() {
    super.initState();
    blockedUsersFuture = loadCurrentBlockedUsers();
  }

  void refreshBlockedUsers() {
    if (!mounted) {
      return;
    }

    setState(() {
      blockedUsersFuture = loadCurrentBlockedUsers();
    });
  }

  Widget blockedUserAvatar(FriendUserData user) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => blockedUserFallbackAvatar(user),
              )
            : blockedUserFallbackAvatar(user),
      ),
    );
  }

  Widget blockedUserFallbackAvatar(FriendUserData user) {
    final letter = user.username.trim().isEmpty
        ? '?'
        : user.username.trim().substring(0, 1).toUpperCase();

    return Center(
      child: CcsText(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> unblockUser(FriendUserData user) async {
    if (busyUserIds.contains(user.uid)) {
      return;
    }

    setState(() => busyUserIds.add(user.uid));
    try {
      await unblockUserById(user.uid);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            trText('User unblocked.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      refreshBlockedUsers();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            localizedFriendActionError(error, 'Could not unblock user.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => busyUserIds.remove(user.uid));
      }
    }
  }

  Widget blockedUserTile(FriendUserData user) {
    final busy = busyUserIds.contains(user.uid);

    return InkWell(
      onTap: user.deleted
          ? null
          : () => openUserProfile(
              context,
              uid: user.uid,
              fallbackUsername: user.username,
            ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelGlass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            blockedUserAvatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: CcsText(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      UserPrimaryBadge(
                        role: user.role,
                        verified: user.verified,
                        globalChatModerator: user.globalChatModerator,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  CcsText(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => unblockUser(user),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : const Icon(Icons.lock_open, size: 16),
              label: CcsText(trText('Unblock user')),
              style: OutlinedButton.styleFrom(
                foregroundColor: blue,
                side: BorderSide(color: blue.withValues(alpha: 0.7)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText('Blacklist')),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: trText('Refresh'),
            onPressed: refreshBlockedUsers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<FriendUserData>>(
        future: blockedUsersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: blue));
          }

          final users = snapshot.data ?? const <FriendUserData>[];
          if (users.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: EmptyStateCard(
                icon: Icons.block,
                title: trText('No blocked users'),
                text: trText('Blocked users will appear here.'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [for (final user in users) blockedUserTile(user)],
          );
        },
      ),
    );
  }
}
