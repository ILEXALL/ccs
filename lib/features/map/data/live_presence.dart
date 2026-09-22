import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, userPresenceDocument, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/shared/utils/date_formatting.dart' show twoDigits;

Future<LiveLocationData?> loadCurrentLiveLocationForUser(String uid) async {
  final snapshot = await liveLocationsCollection().doc(uid).debugGet();

  if (!snapshot.exists) {
    return null;
  }

  final location = LiveLocationData.fromFirestore(snapshot);
  return location.isActive ? location : null;
}

const int onlinePresenceFreshMillis = 4 * 60 * 1000;

bool isOnlinePresenceFresh(int lastSeenAtMillis) {
  if (lastSeenAtMillis <= 0) {
    return false;
  }

  return DateTime.now().millisecondsSinceEpoch - lastSeenAtMillis <=
      onlinePresenceFreshMillis;
}

bool liveLocationShareIsFresh(int? expiresAtMillis) {
  return expiresAtMillis != null &&
      expiresAtMillis > DateTime.now().millisecondsSinceEpoch;
}

bool userAppearsOnlineFromPresence({
  required bool isOnline,
  required int lastSeenAtMillis,
  required bool isSharingLiveLocation,
  required int? liveLocationExpiresAtMillis,
}) {
  return (isOnline && isOnlinePresenceFresh(lastSeenAtMillis)) ||
      (isSharingLiveLocation &&
          liveLocationShareIsFresh(liveLocationExpiresAtMillis));
}

bool isSameLocalDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String lastOnlineLabelFromMillis(int lastSeenAtMillis) {
  if (lastSeenAtMillis <= 0) {
    return trText('Last online unknown');
  }

  final seenAt = DateTime.fromMillisecondsSinceEpoch(
    lastSeenAtMillis,
  ).toLocal();
  final now = DateTime.now();
  final difference = now.difference(seenAt);
  final time = '${twoDigits(seenAt.hour)}:${twoDigits(seenAt.minute)}';

  if (difference.inSeconds < 90) {
    return trText('Last online just now');
  }

  if (isSameLocalDay(seenAt, now)) {
    return '${trText('Last online today at')} $time';
  }

  final yesterday = now.subtract(const Duration(days: 1));
  if (isSameLocalDay(seenAt, yesterday)) {
    return '${trText('Last online yesterday at')} $time';
  }

  final date =
      '${twoDigits(seenAt.day)}.${twoDigits(seenAt.month)}.${seenAt.year}';
  return '${trText('Last online on')} $date $time';
}

Future<void> updateCurrentUserPresenceFields(
  Map<String, Object?> data, {
  String label = 'presence: current user update',
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  try {
    await userPresenceDocument(firebaseUser.uid).debugSet(
      {
        // A live-location action can create presence before the first heartbeat.
        'isOnline': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
      label,
    );
  } catch (_) {
    // Presence should never block the app if Firebase temporarily fails.
  }
}

Future<void> updateCurrentUserOnlinePresence({required bool isOnline}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final serverNow = FieldValue.serverTimestamp();
  final presenceData = <String, Object?>{
    'isOnline': isOnline,
    'lastSeenAt': serverNow,
    'updatedAt': serverNow,
  };

  await updateCurrentUserPresenceFields(
    presenceData,
    label: isOnline
        ? 'presence: current user heartbeat'
        : 'presence: current user offline',
  );

  if (firebaseUser == null) {
    return;
  }

  try {
    await usersCollection()
        .doc(firebaseUser.uid)
        .debugSet(
          presenceData,
          SetOptions(merge: true),
          isOnline
              ? 'users: current user online heartbeat'
              : 'users: current user offline',
        );
  } catch (_) {
    // Presence should never block the app if Firebase temporarily fails.
  }
}
