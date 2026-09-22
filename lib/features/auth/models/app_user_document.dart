import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show nullableTimestampMillisFromFirebase, stringFromFirebase;
import 'package:ccs_app/features/auth/data/account_bans.dart'
    show userBanReasonFromFirebase;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show
        moderatorCountryCodesFromFirebase,
        userDataHasCommunityModerationAccess;
import 'package:ccs_app/shared/models/user_role.dart'
    show roleFromFirebase, userRoleIsStaff;

AppUser appUserFromCurrentUserDocument(
  DocumentSnapshot<Map<String, dynamic>> snapshot,
) {
  final data = snapshot.data() ?? {};
  final bannedUntilMillis = nullableTimestampMillisFromFirebase(
    data['bannedUntil'],
  );
  final role = roleFromFirebase(data['role']);

  return AppUser(
    // The authenticated document path is authoritative, including legacy
    // profiles whose stored uid is blank or outdated.
    uid: snapshot.id,
    name: stringFromFirebase(data['name'], currentUser.name),
    username: stringFromFirebase(data['username'], currentUser.username),
    email: stringFromFirebase(data['email'], currentUser.email),
    photoUrl: data['photoUrl'] is String
        ? data['photoUrl'] as String
        : currentUser.photoUrl,
    bio: stringFromFirebase(data['bio'], currentUser.bio),
    avatarPath: data['avatarPath'] is String
        ? data['avatarPath'] as String
        : currentUser.avatarPath,
    role: role,
    verified: userRoleIsStaff(role) || data['verified'] == true,
    globalChatModerator: userDataHasCommunityModerationAccess(data),
    moderatorCountryCodes: moderatorCountryCodesFromFirebase(
      data['moderatorCountryCodes'],
    ),
    city: stringFromFirebase(data['city'], currentUser.city),
    country: stringFromFirebase(data['country'], currentUser.country),
    banned: data['banned'] == true,
    bannedUntilMillis: bannedUntilMillis,
    banReason: userBanReasonFromFirebase(data),
  );
}
