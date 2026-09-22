import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userNotificationsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        mapFromFirebase,
        nullableTimestampMillisFromFirebase,
        stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension, FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent, trySendPushNotificationEvent;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show userDataAllowsSpotCountry;
import 'package:ccs_app/shared/models/countries.dart'
    show countryIsoCode, spotCountryKey;

const int maxCommunityPushRecipientUsers = 500;

// Notification switches must take effect immediately. Caching an audience even
// briefly can keep a user in a sender's recipient list after they turn a
// notification category off.
const Duration communityPushRecipientCacheDuration = Duration.zero;

final Map<String, List<String>> communityPushRecipientCache =
    <String, List<String>>{};

final Map<String, int> communityPushRecipientCacheAtMillis = <String, int>{};

bool notificationPreferenceEnabledInUserData(
  Map<String, dynamic> data,
  String preferenceKey,
) {
  final nestedSettings = mapFromFirebase(data['settings']);
  if (data[preferenceKey] is bool) {
    return data[preferenceKey] == true;
  }
  if (nestedSettings[preferenceKey] is bool) {
    return nestedSettings[preferenceKey] == true;
  }
  return true;
}

bool userDataHasActiveBan(Map<String, dynamic> data, int nowMillis) {
  if (data['banned'] != true) {
    return false;
  }

  final bannedUntilMillis = nullableTimestampMillisFromFirebase(
    data['bannedUntil'],
  );
  return bannedUntilMillis == null || bannedUntilMillis > nowMillis;
}

Future<List<String>?> communityPushRecipientUserIds({
  required String preferenceKey,
  String spotCountry = '',
  String communityCountryCode = '',
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    return null;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final cleanCommunityCountryCode = communityCountryCode.trim().toUpperCase();
  final cacheKey =
      '$preferenceKey|${spotCountryKey(spotCountry)}|$cleanCommunityCountryCode';
  final cachedAtMillis = communityPushRecipientCacheAtMillis[cacheKey];
  final cached = communityPushRecipientCache[cacheKey];
  if (cachedAtMillis != null &&
      cached != null &&
      nowMillis - cachedAtMillis <
          communityPushRecipientCacheDuration.inMilliseconds) {
    return cached.where((uid) => uid != firebaseUser.uid).toList();
  }

  try {
    final snapshot = await usersCollection()
        .limit(maxCommunityPushRecipientUsers)
        .debugGet(
          null,
          'notifications: community push recipients ($preferenceKey)',
        );
    final recipients = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uid = stringFromFirebase(data['uid'], doc.id).trim();
      if (uid.isEmpty ||
          data['deleted'] == true ||
          userDataHasActiveBan(data, nowMillis) ||
          !notificationPreferenceEnabledInUserData(data, preferenceKey) ||
          (cleanCommunityCountryCode.isNotEmpty &&
              (countryIsoCode(stringFromFirebase(data['country'], '')) ??
                      'LV') !=
                  cleanCommunityCountryCode) ||
          !userDataAllowsSpotCountry(data, spotCountry)) {
        continue;
      }
      recipients.add(uid);
    }

    final cachedRecipients = recipients.toList(growable: false);
    communityPushRecipientCache[cacheKey] = cachedRecipients;
    communityPushRecipientCacheAtMillis[cacheKey] = nowMillis;
    return cachedRecipients.where((uid) => uid != firebaseUser.uid).toList();
  } catch (error, stack) {
    // Preferences are a hard opt-out. If the client cannot verify the
    // recipients, fail closed instead of broadcasting and risking a
    // notification to somebody who disabled this category.
    debugPrint('Could not load community push recipients: $error');
    debugPrint('$stack');
    return const <String>[];
  }
}

Future<void> createCommunityNotificationCenterItems({
  required List<String> recipientUserIds,
  required String type,
  required String notificationId,
  required String title,
  required String body,
  Map<String, Object?> extra = const <String, Object?>{},
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null || recipientUserIds.isEmpty) {
    return;
  }

  final cleanRecipients = recipientUserIds
      .map((uid) => uid.trim())
      .where((uid) => uid.isNotEmpty && uid != firebaseUser.uid)
      .toSet()
      .toList(growable: false);
  if (cleanRecipients.isEmpty) {
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  try {
    // Keep every batch below Firestore's 500-operation limit. These documents
    // are the in-app bell fallback when the deployed push endpoint does not yet
    // understand a new community notification type.
    for (var offset = 0; offset < cleanRecipients.length; offset += 400) {
      final end = math.min(offset + 400, cleanRecipients.length);
      final batch = FirebaseFirestore.instance.batch();

      for (final recipientUid in cleanRecipients.sublist(offset, end)) {
        batch.debugSet(
          userNotificationsCollection().doc('${notificationId}_$recipientUid'),
          {
            'userId': recipientUid,
            'type': type,
            'title': title,
            'body': body,
            'actorUserId': firebaseUser.uid,
            'actorUsername': currentUser.username,
            'senderUserId': firebaseUser.uid,
            'senderUsername': currentUser.username,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMillis': nowMillis,
            ...extra,
          },
          SetOptions(merge: true),
          'notifications: community bell fallback',
        );
      }

      await batch.debugCommit();
    }
    debugPrint(
      'Community bell items created. type=$type recipients=${cleanRecipients.length}',
    );
  } catch (error, stack) {
    debugPrint('Community bell fallback failed: $error');
    debugPrint('$stack');
  }
}

Future<void> sendCommunityPushNotificationEvent({
  required String type,
  required String preferenceKey,
  required String notificationId,
  required String title,
  required String body,
  String communityCountryCode = '',
  Map<String, Object?> extra = const <String, Object?>{},
}) async {
  if (type == 'forum_reply') {
    // The server resolves both the bell audience and targeted push recipients.
    await sendPushNotificationEvent({
      ...extra,
      'type': type,
      'notificationId': notificationId,
      'audience': 'all_users',
    });
    return;
  }

  final recipients = await communityPushRecipientUserIds(
    preferenceKey: preferenceKey,
    communityCountryCode: communityCountryCode,
  );
  if (recipients != null &&
      recipients.isEmpty &&
      type != 'global_chat_message' &&
      type != 'forum_reply') {
    debugPrint(
      'Community push skipped because no eligible recipients were found. '
      'type=$type notificationId=$notificationId',
    );
    return;
  }

  if (recipients != null) {
    await createCommunityNotificationCenterItems(
      recipientUserIds: recipients,
      type: type,
      notificationId: notificationId,
      title: title,
      body: body,
      extra: extra,
    );
  }

  final delivered = await trySendPushNotificationEvent({
    ...extra,
    'type': type,
    'preferenceKey': preferenceKey,
    // Use backend audience expansion only when the client cannot read the
    // concrete recipient list. Otherwise keep the payload recipient-only so an
    // older endpoint cannot accidentally broadcast back to the sender.
    if (recipients == null) 'audience': 'all_users',
    'notificationId': notificationId,
    'title': title,
    'body': body,
    if (communityCountryCode.trim().isNotEmpty)
      'countryCode': communityCountryCode.trim().toUpperCase(),
    'recipientUserIds': ?recipients,
    if (recipients != null) 'preferencesAlreadyFiltered': true,
  });
  if (!delivered) {
    debugPrint('Community push was not delivered: $notificationId');
  }
}
