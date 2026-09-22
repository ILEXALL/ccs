import 'dart:async';
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show
        moderatorCountryCodesFromFirebase,
        userDataHasCommunityModerationAccess;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

Future<List<String>> staffUserIdsExcept({
  String? excludedUid,
  String countryCode = '',
}) async {
  final adminSnapshot = await usersCollection()
      .where('role', isEqualTo: 'admin')
      .debugGet(null, 'users: admin user ids query');
  final moderatorSnapshot = await usersCollection()
      .where('role', isEqualTo: 'moderator')
      .debugGet(null, 'users: moderator user ids query');

  final ids = <String>{};
  for (final doc in [...adminSnapshot.docs, ...moderatorSnapshot.docs]) {
    final data = doc.data();
    final uid = stringFromFirebase(data['uid'], doc.id).trim();
    final deleted = data['deleted'] == true;
    final banned = data['banned'] == true;
    if (uid.isNotEmpty &&
        uid != excludedUid &&
        !deleted &&
        !banned &&
        (data['role'] == 'admin' ||
            moderatorCountryCodesFromFirebase(
              data['moderatorCountryCodes'],
            ).contains(countryCode))) {
      ids.add(uid);
    }
  }

  return ids.toList();
}

Future<List<String>> spotReviewStaffUserIdsExcept(
  CarSpot spot, {
  String? excludedUid,
}) async {
  final countryCode = spot.countryCode.trim().toUpperCase();
  final adminSnapshot = await usersCollection()
      .where('role', isEqualTo: 'admin')
      .debugGet(null, 'users: spot review admin ids query');
  final moderatorSnapshot = await usersCollection()
      .where('role', isEqualTo: 'moderator')
      .debugGet(null, 'users: regional spot moderator ids query');

  final ids = <String>{};
  for (final doc in adminSnapshot.docs) {
    final data = doc.data();
    final uid = stringFromFirebase(data['uid'], doc.id).trim();
    if (uid.isNotEmpty &&
        uid != excludedUid &&
        data['deleted'] != true &&
        data['banned'] != true) {
      ids.add(uid);
    }
  }

  if (countryCode.isNotEmpty) {
    for (final doc in moderatorSnapshot.docs) {
      final data = doc.data();
      final uid = stringFromFirebase(data['uid'], doc.id).trim();
      final assignedCountries = moderatorCountryCodesFromFirebase(
        data['moderatorCountryCodes'],
      );
      if (uid.isNotEmpty &&
          uid != excludedUid &&
          data['deleted'] != true &&
          data['banned'] != true &&
          assignedCountries.contains(countryCode)) {
        ids.add(uid);
      }
    }
  }

  return ids.toList(growable: false);
}

Future<List<String>> communityModerationUserIdsExcept({
  String? excludedUid,
  required String countryCode,
}) async {
  final snapshot = await usersCollection().debugGet();
  return snapshot.docs
      .where((doc) {
        final data = doc.data();
        if (doc.id == excludedUid ||
            data['deleted'] == true ||
            data['banned'] == true)
          return false;
        if (data['role'] == 'admin') return true;
        return (data['role'] == 'moderator' ||
                userDataHasCommunityModerationAccess(data)) &&
            moderatorCountryCodesFromFirebase(
              data['moderatorCountryCodes'],
            ).contains(countryCode);
      })
      .map((doc) => doc.id)
      .toList();
}

Future<List<String>> adminUserIdsExcept({String? excludedUid}) async {
  final snapshot = await usersCollection()
      .where('role', isEqualTo: 'admin')
      .debugGet(null, 'users: admin-only user ids query');

  final ids = <String>[];
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final uid = stringFromFirebase(data['uid'], doc.id).trim();
    if (uid.isNotEmpty &&
        uid != excludedUid &&
        data['deleted'] != true &&
        data['banned'] != true) {
      ids.add(uid);
    }
  }

  return ids;
}
