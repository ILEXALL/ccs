import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        nullableTimestampMillisFromFirebase,
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase,
        uniqueNonEmptyStrings;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/account_bans.dart'
    show userBanLabel, userBanReasonFromFirebase;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show lastOnlineLabelFromMillis, userAppearsOnlineFromPresence;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show moderatorCountryCodesFromFirebase;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase;

class AdminUserData {
  final String uid;
  final String username;
  final String name;
  final String email;
  final String country;
  final UserRole role;
  final bool verified;
  final bool banned;
  final int? bannedUntilMillis;
  final String banReason;
  final List<String> deviceIds;
  final bool globalChatModerator;
  final Set<String> moderatorCountryCodes;
  final bool deleted;
  final bool isOnline;
  final int lastSeenAtMillis;

  const AdminUserData({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    this.country = '',
    required this.role,
    required this.verified,
    required this.banned,
    this.bannedUntilMillis,
    this.banReason = '',
    this.deviceIds = const [],
    this.globalChatModerator = false,
    this.moderatorCountryCodes = const <String>{},
    required this.deleted,
    this.isOnline = false,
    this.lastSeenAtMillis = 0,
  });

  bool get banActive {
    return banned &&
        (bannedUntilMillis == null ||
            bannedUntilMillis! > DateTime.now().millisecondsSinceEpoch);
  }

  bool get appearsOnline => userAppearsOnlineFromPresence(
    isOnline: isOnline,
    lastSeenAtMillis: lastSeenAtMillis,
    isSharingLiveLocation: false,
    liveLocationExpiresAtMillis: null,
  );

  String get statusLabel {
    if (deleted) {
      return 'Deleted';
    }

    if (appearsOnline) {
      return trText('Online');
    }

    if (lastSeenAtMillis > 0) {
      return lastOnlineLabelFromMillis(lastSeenAtMillis);
    }

    return userBanLabel(banned: banned, bannedUntilMillis: bannedUntilMillis);
  }

  factory AdminUserData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final bannedUntilMillis = nullableTimestampMillisFromFirebase(
      data['bannedUntil'],
    );
    final deviceIds = uniqueNonEmptyStrings([
      ...stringListFromFirebase(data['deviceIds'], const []),
      stringFromFirebase(data['lastDeviceId'], ''),
      ...stringListFromFirebase(data['knownDeviceIdsAtBan'], const []),
    ]);

    return AdminUserData(
      uid: stringFromFirebase(data['uid'], doc.id),
      username: stringFromFirebase(data['username'], 'ccs_driver'),
      name: stringFromFirebase(data['name'], 'CCS Driver'),
      email: stringFromFirebase(data['email'], ''),
      country: stringFromFirebase(data['country'], ''),
      role: roleFromFirebase(data['role']),
      verified:
          roleFromFirebase(data['role']) == UserRole.admin ||
          data['verified'] == true,
      banned: data['banned'] == true,
      bannedUntilMillis: bannedUntilMillis,
      banReason: userBanReasonFromFirebase(data),
      deviceIds: deviceIds,
      globalChatModerator:
          data['globalChatModerator'] == true ||
          data['globalModerator'] == true,
      moderatorCountryCodes: moderatorCountryCodesFromFirebase(
        data['moderatorCountryCodes'],
      ),
      deleted: data['deleted'] == true,
      isOnline: data['isOnline'] == true,
      lastSeenAtMillis: timestampMillisFromFirebase(data['lastSeenAt']),
    );
  }
}

class AdminBanInput {
  final int days;
  final String reason;

  const AdminBanInput({required this.days, required this.reason});
}
