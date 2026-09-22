import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        nullableTimestampMillisFromFirebase,
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show userAppearsOnlineFromPresence;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, userRoleIsStaff;

class FriendUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final bool verified;
  final UserRole role;
  final bool globalChatModerator;
  final bool banned;
  final int? bannedUntilMillis;
  final bool deleted;
  final bool isOnline;
  final int lastSeenAtMillis;
  final bool isSharingLiveLocation;
  final int? liveLocationExpiresAtMillis;
  final List<String> liveLocationVisibleToUserIds;

  const FriendUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.verified,
    required this.role,
    this.globalChatModerator = false,
    required this.banned,
    this.bannedUntilMillis,
    required this.deleted,
    this.isOnline = false,
    this.lastSeenAtMillis = 0,
    this.isSharingLiveLocation = false,
    this.liveLocationExpiresAtMillis,
    this.liveLocationVisibleToUserIds = const [],
  });

  FriendUserData withPresenceFromMap(Map<String, dynamic>? data) {
    if (data == null) {
      return this;
    }

    return FriendUserData(
      uid: uid,
      username: username,
      name: name,
      email: email,
      photoUrl: photoUrl,
      avatarPath: avatarPath,
      verified: verified,
      role: role,
      globalChatModerator: globalChatModerator,
      banned: banned,
      bannedUntilMillis: bannedUntilMillis,
      deleted: deleted,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
      isSharingLiveLocation: data['isSharingLiveLocation'] == true,
      liveLocationExpiresAtMillis: nullableTimestampMillisFromFirebase(
        data['liveLocationExpiresAt'],
      ),
      liveLocationVisibleToUserIds: stringListFromFirebase(
        data['liveLocationVisibleToUserIds'],
        liveLocationVisibleToUserIds,
      ),
    );
  }

  bool get canSeeLiveLocationPresence {
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;

    return currentUid.trim().isNotEmpty &&
        (uid == currentUid ||
            liveLocationVisibleToUserIds.contains(currentUid));
  }

  bool get appearsOnline => userAppearsOnlineFromPresence(
    isOnline: isOnline,
    lastSeenAtMillis: lastSeenAtMillis,
    isSharingLiveLocation: isSharingLiveLocation && canSeeLiveLocationPresence,
    liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
  );

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  bool get canAppearInUserLists => !deleted && !banActive;

  factory FriendUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final isCurrentProfile =
        doc.id == currentUser.uid || data['uid'] == currentUser.uid;
    final role = isCurrentProfile
        ? currentUser.role
        : roleFromFirebase(data['role']);
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );

    return FriendUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      role: role,
      verified: isCurrentProfile
          ? currentUser.verified
          : userRoleIsStaff(role) || data['verified'] == true,
      globalChatModerator: isCurrentProfile
          ? currentUser.globalChatModerator
          : userDataHasCommunityModerationAccess(data),
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      deleted: data['deleted'] == true,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
      isSharingLiveLocation: data['isSharingLiveLocation'] == true,
      liveLocationExpiresAtMillis: nullableTimestampMillisFromFirebase(
        data['liveLocationExpiresAt'],
      ),
      liveLocationVisibleToUserIds: stringListFromFirebase(
        data['liveLocationVisibleToUserIds'],
        const [],
      ),
    );
  }
}
