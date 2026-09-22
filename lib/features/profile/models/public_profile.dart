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
import 'package:ccs_app/features/profile/models/garage_car.dart'
    show GarageCar, garageCarsFromFirebase;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, userRoleIsStaff;

class PublicUserProfileData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String? photoUrl;
  final String? avatarPath;
  final String bio;
  final String city;
  final String country;
  final UserRole role;
  final bool verified;
  final bool globalChatModerator;
  final UserSettingsData settings;
  final List<GarageCar> garage;
  final bool deleted;
  final bool isOnline;
  final int lastSeenAtMillis;
  final bool isSharingLiveLocation;
  final int? liveLocationExpiresAtMillis;
  final List<String> blockedUserIds;

  const PublicUserProfileData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.photoUrl,
    this.avatarPath,
    required this.bio,
    required this.city,
    required this.country,
    required this.role,
    required this.verified,
    this.globalChatModerator = false,
    required this.settings,
    required this.garage,
    required this.deleted,
    this.isOnline = false,
    this.lastSeenAtMillis = 0,
    this.isSharingLiveLocation = false,
    this.liveLocationExpiresAtMillis,
    this.blockedUserIds = const [],
  });

  bool get currentViewerIsBlocked {
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    return currentUid.trim().isNotEmpty && blockedUserIds.contains(currentUid);
  }

  bool get canCurrentUserView {
    if (userRoleIsStaff(currentUser.role)) {
      return true;
    }

    if (currentViewerIsBlocked) {
      return false;
    }

    return currentUser.uid == uid || settings.publicProfile;
  }

  bool get appearsOnline => userAppearsOnlineFromPresence(
    isOnline: isOnline,
    lastSeenAtMillis: lastSeenAtMillis,
    isSharingLiveLocation: isSharingLiveLocation,
    liveLocationExpiresAtMillis: liveLocationExpiresAtMillis,
  );

  PublicUserProfileData copyWith({
    bool? isOnline,
    int? lastSeenAtMillis,
    bool? isSharingLiveLocation,
    int? liveLocationExpiresAtMillis,
  }) {
    return PublicUserProfileData(
      uid: uid,
      username: username,
      name: name,
      email: email,
      photoUrl: photoUrl,
      avatarPath: avatarPath,
      bio: bio,
      city: city,
      country: country,
      role: role,
      verified: verified,
      globalChatModerator: globalChatModerator,
      settings: settings,
      garage: garage,
      deleted: deleted,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAtMillis: lastSeenAtMillis ?? this.lastSeenAtMillis,
      isSharingLiveLocation:
          isSharingLiveLocation ?? this.isSharingLiveLocation,
      liveLocationExpiresAtMillis:
          liveLocationExpiresAtMillis ?? this.liveLocationExpiresAtMillis,
      blockedUserIds: blockedUserIds,
    );
  }

  String get cityCountry {
    return [
      city.trim(),
      country.trim(),
    ].where((part) => part.isNotEmpty).join(', ');
  }

  factory PublicUserProfileData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final isCurrentProfile =
        doc.id == currentUser.uid || data['uid'] == currentUser.uid;
    final role = isCurrentProfile
        ? currentUser.role
        : roleFromFirebase(data['role']);

    return PublicUserProfileData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      photoUrl: data['photoUrl'] is String ? data['photoUrl'] as String : null,
      avatarPath: data['avatarPath'] is String
          ? data['avatarPath'] as String
          : null,
      bio: stringFromFirebase(data['bio'], 'Find. Drive. Shoot.'),
      city: stringFromFirebase(data['city'], ''),
      country: stringFromFirebase(data['country'], ''),
      role: role,
      verified: isCurrentProfile
          ? currentUser.verified
          : userRoleIsStaff(role) || data['verified'] == true,
      globalChatModerator: isCurrentProfile
          ? currentUser.globalChatModerator
          : userDataHasCommunityModerationAccess(data),
      settings: UserSettingsData.fromFirebase(data['settings']),
      garage: garageCarsFromFirebase(data['garage']),
      deleted: data['deleted'] == true,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
      isSharingLiveLocation: data['isSharingLiveLocation'] == true,
      liveLocationExpiresAtMillis: nullableTimestampMillisFromFirebase(
        data['liveLocationExpiresAt'],
      ),
      blockedUserIds: stringListFromFirebase(data['blockedUserIds'], const []),
    );
  }
}
