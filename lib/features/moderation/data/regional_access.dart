import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/models/countries.dart'
    show countryIsoCode, countryNamesByIso;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;

Set<String> moderatorCountryCodesFromFirebase(Object? value) {
  if (value is! Iterable) {
    return <String>{};
  }

  return value
      .whereType<String>()
      .map((code) => code.trim().toUpperCase())
      .where(countryNamesByIso.containsKey)
      .toSet();
}

bool get currentUserRegionIsRestricted {
  final countryCode = countryIsoCode(currentUser.country);
  return countryCode != null &&
      maintenanceModeConfig.value.bannedCountryCodes.contains(countryCode);
}

bool currentUserCanModerateCountry(
  String countryCode, {
  bool community = false,
}) {
  if (currentUser.role == UserRole.admin) return true;
  final code = countryCode.trim().toUpperCase();
  return (currentUser.role == UserRole.moderator ||
          (community && currentUser.globalChatModerator)) &&
      countryNamesByIso.containsKey(code) &&
      currentUser.moderatorCountryCodes.contains(code);
}

bool currentUserCanModerateCommunityData(Map<String, dynamic> data) =>
    currentUserCanModerateCountry(
      stringFromFirebase(data['countryCode'], 'LV'),
      community: true,
    );

bool currentUserCanManageProfileCountry(String country) =>
    currentUserCanModerateCountry(countryIsoCode(country) ?? '');

bool moderationNotificationAllowed(Map<String, dynamic> data) {
  final type = stringFromFirebase(data['type'], '');
  if (!const {
    'spot_pending_review',
    'forum_topic_pending',
    'global_chat_admin',
    'spot_removal_request',
    'user_report_new',
    'moderator_user_banned',
  }.contains(type)) {
    return true;
  }
  if (currentUser.role == UserRole.admin) return true;
  if (type == 'moderator_user_banned') return false;
  final nested = mapFromFirebase(data['data']);
  final code = stringFromFirebase(
    data['countryCode'],
    stringFromFirebase(nested['countryCode'], ''),
  ).trim().toUpperCase();
  return currentUserCanModerateCountry(
    code,
    community: type == 'forum_topic_pending' || type == 'global_chat_admin',
  );
}

bool currentUserCanModerateSpot(CarSpot spot) {
  if (currentUser.role == UserRole.admin) {
    return true;
  }
  if (currentUser.role != UserRole.moderator) {
    return false;
  }

  // Regional moderation is based on the canonical country code stored on the
  // spot. Legacy spots are backfilled by an admin before moderators see them.
  final storedCode = spot.countryCode.trim().toUpperCase();
  return storedCode.isNotEmpty &&
      currentUser.moderatorCountryCodes.contains(storedCode);
}

bool userDataHasCommunityModerationAccess(Map<String, dynamic>? data) {
  return data?['globalChatModerator'] == true ||
      data?['globalModerator'] == true;
}

Future<bool> currentUserHasCommunityModerationAccess() async {
  if (FirebaseAuth.instance.currentUser == null) return false;
  return currentUser.role == UserRole.admin ||
      ((currentUser.role == UserRole.moderator ||
              currentUser.globalChatModerator) &&
          currentUser.moderatorCountryCodes.isNotEmpty);
}

bool get currentUserCanUseVerifiedOnlySpots {
  return userRoleIsStaff(currentUser.role) || currentUser.verified;
}

bool currentUserCanManageSpotBusiness(CarSpot spot) {
  return spot.supportsContacts &&
      (currentUser.role == UserRole.admin ||
          (currentUser.role == UserRole.moderator &&
              currentUserCanModerateSpot(spot)) ||
          (spot.ownerUid.isNotEmpty && spot.ownerUid == currentUser.uid));
}
