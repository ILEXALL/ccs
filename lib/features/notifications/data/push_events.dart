import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart' show pushNotificationUrls;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, stringListFromFirebase;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show userNotificationPreferenceEnabled;

final Map<String, int> _recentPushEventSentAtMillis = <String, int>{};

String pushNotificationEventDedupKey(
  Map<String, Object?> event,
  String senderUid,
) {
  final notificationId = stringFromFirebase(event['notificationId'], '').trim();
  if (notificationId.isNotEmpty) {
    return '$senderUid|notificationId:$notificationId';
  }

  final type = stringFromFirebase(event['type'], '').trim();
  final chatId = stringFromFirebase(event['chatId'], '').trim();
  final messageId = stringFromFirebase(event['messageId'], '').trim();
  if (type == 'chat_message' && chatId.isNotEmpty && messageId.isNotEmpty) {
    return '$senderUid|chat:$chatId:$messageId';
  }

  final reviewId = stringFromFirebase(event['reviewId'], '').trim();
  if (type == 'spot_comment' && reviewId.isNotEmpty) {
    return '$senderUid|spot_comment:$reviewId';
  }

  final likeId = stringFromFirebase(event['likeId'], '').trim();
  if (type == 'spot_like' && likeId.isNotEmpty) {
    return '$senderUid|spot_like:$likeId';
  }

  final spotId = stringFromFirebase(event['spotId'], '').trim();
  if (type.isNotEmpty && spotId.isNotEmpty) {
    return '$senderUid|$type:$spotId';
  }

  return '$senderUid|${event.toString()}';
}

bool shouldSendPushNotificationEvent(
  Map<String, Object?> event,
  String senderUid,
) {
  final key = pushNotificationEventDedupKey(event, senderUid);
  final now = DateTime.now().millisecondsSinceEpoch;
  final previous = _recentPushEventSentAtMillis[key];
  if (previous != null && now - previous < 10000) {
    debugPrint('Duplicate push event skipped: $key');
    return false;
  }

  _recentPushEventSentAtMillis[key] = now;
  _recentPushEventSentAtMillis.removeWhere((_, value) => now - value > 60000);
  return true;
}

Future<bool> trySendPushNotificationEvent(
  Map<String, Object?> event, {
  List<String> endpoints = pushNotificationUrls,
  bool deduplicate = true,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    debugPrint(
      'Push event skipped because there is no signed-in Firebase user. event=$event',
    );
    return false;
  }

  final dedupKey = pushNotificationEventDedupKey(event, firebaseUser.uid);
  if (deduplicate &&
      !shouldSendPushNotificationEvent(event, firebaseUser.uid)) {
    // Another identical event was already accepted or is currently in flight.
    return true;
  }

  var recipientUserIds = stringListFromFirebase(
    event['recipientUserIds'],
    const <String>[],
  ).where((uid) => uid.trim().isNotEmpty && uid != firebaseUser.uid).toSet();

  final preferenceKey = stringFromFirebase(event['preferenceKey'], '').trim();
  if (recipientUserIds.isNotEmpty &&
      preferenceKey.isNotEmpty &&
      event['preferencesAlreadyFiltered'] != true) {
    final allowedRecipients = <String>{};
    for (final recipientUid in recipientUserIds) {
      if (await userNotificationPreferenceEnabled(
        recipientUid,
        preferenceKey,
      )) {
        allowedRecipients.add(recipientUid);
      }
    }
    recipientUserIds = allowedRecipients;
  }

  if (event.containsKey('recipientUserIds') && recipientUserIds.isEmpty) {
    _recentPushEventSentAtMillis.remove(dedupKey);
    debugPrint('Push event skipped because it has no recipients. event=$event');
    return false;
  }

  Object? lastError;
  StackTrace? lastStack;

  for (var attempt = 0; attempt < 2; attempt++) {
    String? idToken;
    try {
      idToken = await firebaseUser.getIdToken(attempt > 0);
    } catch (error, stack) {
      lastError = error;
      lastStack = stack;
      debugPrint('Could not obtain Firebase ID token for push: $error');
      continue;
    }
    if (idToken == null || idToken.trim().isEmpty) {
      lastError = StateError('Firebase ID token is empty.');
      continue;
    }

    for (final endpoint in endpoints) {
      try {
        final payload = <String, Object?>{
          ...event,
          if (recipientUserIds.isNotEmpty)
            'recipientUserIds': recipientUserIds.toList(),
          'senderUserId': firebaseUser.uid,
          'sentAtMillis': DateTime.now().millisecondsSinceEpoch,
        };
        debugPrint('Sending push event to $endpoint: $payload');
        final response = await postJsonToUrl(
          endpoint,
          payload,
          headers: {HttpHeaders.authorizationHeader: 'Bearer $idToken'},
        );
        if (response['ok'] == false) {
          throw StateError(
            stringFromFirebase(
              response['error'],
              'Push backend rejected event.',
            ),
          );
        }
        debugPrint('Push event accepted by $endpoint: $event');
        return true;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        debugPrint('Push endpoint failed ($endpoint): $error');
      }
    }

    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  // Permit a later retry when every endpoint failed.
  _recentPushEventSentAtMillis.remove(dedupKey);
  debugPrint('Push event failed on every configured endpoint: $lastError');
  if (lastStack != null) {
    debugPrint('$lastStack');
  }
  return false;
}

Future<void> sendPushNotificationEvent(Map<String, Object?> event) async {
  await trySendPushNotificationEvent(event);
}
