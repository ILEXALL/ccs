import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, userRoleIsStaff;

enum UserPrimaryBadgeKind { admin, moderator, communityModerator, verified }

UserPrimaryBadgeKind? primaryUserBadgeKind({
  required UserRole role,
  required bool verified,
  bool globalChatModerator = false,
}) {
  if (role == UserRole.admin) {
    return UserPrimaryBadgeKind.admin;
  }
  if (role == UserRole.moderator) {
    return UserPrimaryBadgeKind.moderator;
  }
  if (globalChatModerator) {
    return UserPrimaryBadgeKind.communityModerator;
  }
  if (verified) {
    return UserPrimaryBadgeKind.verified;
  }
  return null;
}

class UserPrimaryBadge extends StatelessWidget {
  final UserRole role;
  final bool verified;
  final bool globalChatModerator;
  final bool compact;
  final bool showLabel;

  const UserPrimaryBadge({
    super.key,
    required this.role,
    required this.verified,
    this.globalChatModerator = false,
    this.compact = false,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = primaryUserBadgeKind(
      role: role,
      verified: verified,
      globalChatModerator: globalChatModerator,
    );
    if (kind == null) {
      return const SizedBox.shrink();
    }

    final color = switch (kind) {
      UserPrimaryBadgeKind.admin => Colors.redAccent,
      UserPrimaryBadgeKind.moderator => blue,
      UserPrimaryBadgeKind.communityModerator => Colors.greenAccent,
      UserPrimaryBadgeKind.verified => blue,
    };
    final icon = switch (kind) {
      UserPrimaryBadgeKind.admin => Icons.workspace_premium_rounded,
      UserPrimaryBadgeKind.moderator => Icons.admin_panel_settings_rounded,
      UserPrimaryBadgeKind.communityModerator => Icons.forum_rounded,
      UserPrimaryBadgeKind.verified => Icons.verified_rounded,
    };
    final label = switch (kind) {
      UserPrimaryBadgeKind.admin => 'Admin',
      UserPrimaryBadgeKind.moderator => 'Moderator',
      UserPrimaryBadgeKind.communityModerator => 'Community moderator',
      UserPrimaryBadgeKind.verified => 'Verified',
    };

    if (!showLabel) {
      return Icon(icon, color: color, size: compact ? 15 : 18);
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: compact ? 12 : 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 110 : 160),
            child: CcsText(
              trText(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserPrimaryBadgeForUid extends StatelessWidget {
  final String uid;
  final UserRole fallbackRole;
  final bool fallbackVerified;
  final bool fallbackGlobalChatModerator;
  final bool compact;

  const UserPrimaryBadgeForUid({
    super.key,
    required this.uid,
    this.fallbackRole = UserRole.user,
    this.fallbackVerified = false,
    this.fallbackGlobalChatModerator = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      return UserPrimaryBadge(
        role: fallbackRole,
        verified: fallbackVerified,
        globalChatModerator: fallbackGlobalChatModerator,
        compact: compact,
      );
    }

    if (cleanUid == currentUser.uid) {
      return UserPrimaryBadge(
        role: currentUser.role,
        verified: currentUser.verified,
        globalChatModerator: currentUser.globalChatModerator,
        compact: compact,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCollection()
          .doc(cleanUid)
          .debugSnapshots('user: primary badge listener'),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return UserPrimaryBadge(
            role: fallbackRole,
            verified: fallbackVerified,
            globalChatModerator: fallbackGlobalChatModerator,
            compact: compact,
          );
        }

        final role = roleFromFirebase(data['role']);
        return UserPrimaryBadge(
          role: role,
          verified: userRoleIsStaff(role) || data['verified'] == true,
          globalChatModerator: userDataHasCommunityModerationAccess(data),
          compact: compact,
        );
      },
    );
  }
}
