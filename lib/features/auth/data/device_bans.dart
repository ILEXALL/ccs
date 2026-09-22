import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show deviceBansCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        nullableTimestampMillisFromFirebase,
        stringFromFirebase,
        uniqueNonEmptyStrings;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/platform/device_identity.dart'
    show cleanDeviceIdForStorage;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/models/admin_user.dart'
    show AdminUserData;

bool deviceBanIsActive(Map<String, dynamic>? data) {
  if (data?['banned'] != true) {
    return false;
  }

  final untilMillis = nullableTimestampMillisFromFirebase(data?['bannedUntil']);
  return untilMillis == null ||
      untilMillis > DateTime.now().millisecondsSinceEpoch;
}

String deviceBanReasonFromFirebase(Map<String, dynamic>? data) {
  final reason = stringFromFirebase(data?['reason'], '').trim();
  if (reason.isNotEmpty) {
    return reason;
  }

  return stringFromFirebase(
    data?['banReason'],
    'This device is banned.',
  ).trim();
}

Future<void> ensureAppDeviceIsAllowed({required List<String> deviceIds}) async {
  for (final deviceId in uniqueNonEmptyStrings(deviceIds)) {
    final cleanDeviceId = cleanDeviceIdForStorage(deviceId);
    if (cleanDeviceId.isEmpty) {
      continue;
    }

    final snapshot = await deviceBansCollection()
        .doc(cleanDeviceId)
        .debugGet(null, 'login: check device ban');
    final data = snapshot.data();

    if (!snapshot.exists || !deviceBanIsActive(data)) {
      continue;
    }

    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'device-banned',
      message: deviceBanReasonFromFirebase(data),
    );
  }
}

Future<void> saveDeviceBanForUser({
  required String deviceId,
  required AdminUserData user,
  required Timestamp bannedUntil,
  required String reason,
}) async {
  final cleanDeviceId = cleanDeviceIdForStorage(deviceId);
  if (cleanDeviceId.isEmpty) {
    return;
  }

  await deviceBansCollection().doc(cleanDeviceId).debugSet({
    'deviceId': cleanDeviceId,
    'banned': true,
    'bannedUntil': bannedUntil,
    'reason': reason,
    'sourceUserUid': user.uid,
    'sourceUsername': user.username,
    'bannedByUid': currentUser.uid,
    'bannedBy': currentUser.username,
    'bannedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
