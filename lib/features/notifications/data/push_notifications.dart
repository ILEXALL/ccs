import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/location/startup_location.dart';
import 'package:ccs_app/features/notifications/models/notification_freshness.dart';
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show systemNotificationsChannel;
import 'package:ccs_app/features/auth/data/auth_state.dart' show firebaseReady;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show moderationNotificationAllowed;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show
        globalChatIsActivelyVisibleForNotifications,
        notificationCenterUnreadCount;
import 'package:ccs_app/features/notifications/models/notification_types.dart'
    show selfAuthoredMessageNotificationTypes;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show userSettings;

StreamSubscription<String>? pushTokenRefreshSubscription;

StreamSubscription<RemoteMessage>? foregroundPushSubscription;

String? pushInitializationUid;

Future<void>? pushInitializationFuture;

Future<void> registerPushTokenForCurrentUser(String token) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanToken = token.trim();

  if (firebaseUser == null || cleanToken.isEmpty) {
    debugPrint(
      'Push token registration skipped. firebaseUser=${firebaseUser?.uid}, tokenEmpty=${cleanToken.isEmpty}',
    );
    return;
  }

  try {
    await usersCollection().doc(firebaseUser.uid).debugSet({
      'fcmTokens': FieldValue.arrayUnion([cleanToken]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      'lastFcmTokenPlatform': Platform.operatingSystem,
    }, SetOptions(merge: true));
    debugPrint(
      'Push token registered for ${firebaseUser.uid}: ${cleanToken.substring(0, math.min(12, cleanToken.length))}...',
    );
  } catch (error, stack) {
    debugPrint('Push token registration failed: $error');
    debugPrint('$stack');
  }
}

Future<void> unregisterPushTokenForCurrentUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  try {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null || token.trim().isEmpty) {
      return;
    }

    await usersCollection().doc(firebaseUser.uid).debugSet({
      'fcmTokens': FieldValue.arrayRemove([token]),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error, stack) {
    debugPrint('Push token cleanup failed: $error');
    debugPrint('$stack');
  }
}

String notificationPreferenceKeyForRemoteMessage(RemoteMessage message) {
  final explicitKey = stringFromFirebase(
    message.data['preferenceKey'],
    '',
  ).trim();
  if (explicitKey.isNotEmpty) {
    return explicitKey;
  }

  final type = stringFromFirebase(message.data['type'], '').trim();
  return switch (type) {
    'spot_review_update' ||
    'spot_approved_by_admin' ||
    'spot_rejected_by_admin' => 'reviewNotifications',
    'spot_like' => 'likeNotifications',
    'spot_comment' ||
    'forum_topic_created' ||
    'forum_reply' ||
    'forum_reply_admin' => 'commentNotifications',
    'chat_message' ||
    'global_chat_message' ||
    'global_chat_admin' => 'newMessageNotifications',
    'xp_reward' => 'xpNotifications',
    'new_spot' ||
    'temporary_event' ||
    'temporary_spot_today' => 'newSpotNotifications',
    'friend_nearby' || 'friend_at_spot' => 'friendAtSpotNotifications',
    'friend_live_sharing' => 'friendLiveShareNotifications',
    _ => '',
  };
}

bool localNotificationPreferenceEnabled(String preferenceKey) {
  final settings = userSettings.value;
  return switch (preferenceKey.trim()) {
    'reviewNotifications' => settings.reviewNotifications,
    'likeNotifications' => settings.likeNotifications,
    'commentNotifications' => settings.commentNotifications,
    'newSpotNotifications' => settings.newSpotNotifications,
    'newMessageNotifications' => settings.newMessageNotifications,
    'xpNotifications' => settings.xpNotifications,
    'friendAtSpotNotifications' => settings.friendAtSpotNotifications,
    'friendLiveShareNotifications' => settings.friendLiveShareNotifications,
    _ => true,
  };
}

bool remoteMessageTargetsGlobalChat(RemoteMessage message) {
  final type = stringFromFirebase(message.data['type'], '').trim();
  return type == 'global_chat_message' || type == 'global_chat_admin';
}

Future<void> showForegroundSystemNotification(RemoteMessage message) async {
  if (message.sentTime == null ||
      !message.sentTime!.isAfter(notificationLaunchTime))
    return;
  if (!moderationNotificationAllowed(message.data)) return;
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  final preferenceKey = notificationPreferenceKeyForRemoteMessage(message);
  if (preferenceKey.isNotEmpty &&
      !localNotificationPreferenceEnabled(preferenceKey)) {
    debugPrint(
      'Foreground push skipped because $preferenceKey is disabled. '
      'messageId=${message.messageId}, data=${message.data}',
    );
    return;
  }

  if (remoteMessageTargetsGlobalChat(message) &&
      globalChatIsActivelyVisibleForNotifications) {
    debugPrint(
      'Foreground Global Chat push skipped because Global Chat is visible. '
      'messageId=${message.messageId}',
    );
    return;
  }

  final currentUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (remoteMessageIsSelfAuthoredMessage(message, currentUid)) {
    debugPrint(
      'Foreground push skipped because it was authored by the current user. '
      'messageId=${message.messageId}, data=${message.data}',
    );
    return;
  }

  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] ?? 'CCS';
  final body = notification?.body ?? message.data['body'] ?? '';

  if (body.trim().isEmpty) {
    return;
  }

  try {
    await systemNotificationsChannel.invokeMethod<void>('showNotification', {
      'id': (message.messageId ?? '$title|$body').hashCode & 0x7fffffff,
      'title': title,
      'body': body,
      'badgeCount': math.max(1, notificationCenterUnreadCount.value + 1),
    });
  } catch (error, stack) {
    debugPrint('Foreground push display failed: $error');
    debugPrint('$stack');
  }
}

bool remoteMessageIsSelfAuthoredMessage(
  RemoteMessage message,
  String currentUid,
) {
  final cleanCurrentUid = currentUid.trim();
  if (cleanCurrentUid.isEmpty) {
    return false;
  }

  final data = message.data;
  final type = stringFromFirebase(data['type'], '').trim();
  if (!selfAuthoredMessageNotificationTypes.contains(type)) {
    return false;
  }

  final senderUid = stringFromFirebase(
    data['senderUid'],
    stringFromFirebase(
      data['senderUserId'],
      stringFromFirebase(data['actorUserId'], ''),
    ),
  ).trim();

  return senderUid.isNotEmpty && senderUid == cleanCurrentUid;
}

Future<void> initializePushNotificationsForCurrentUser() {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (!firebaseReady || firebaseUser == null) {
    debugPrint(
      'Push initialization skipped. firebaseReady=$firebaseReady, firebaseUser=${firebaseUser?.uid}',
    );
    return Future<void>.value();
  }

  final existing = pushInitializationFuture;
  if (pushInitializationUid == firebaseUser.uid && existing != null) {
    return existing;
  }

  pushInitializationUid = firebaseUser.uid;
  final initialization = _initializePushNotifications(firebaseUser.uid);
  pushInitializationFuture = initialization;
  return initialization;
}

Future<void> _initializePushNotifications(String expectedUid) async {
  if (FirebaseAuth.instance.currentUser?.uid != expectedUid) {
    return;
  }

  try {
    final messaging = FirebaseMessaging.instance;

    final settings = await runPermissionRequest(
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
    );
    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
      final apnsToken = await messaging.getAPNSToken();
      debugPrint(
        'APNs token ${apnsToken == null || apnsToken.trim().isEmpty ? 'is empty' : 'is available'}.',
      );
    }
    debugPrint('Push permission status: ${settings.authorizationStatus}');

    final token = await messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      debugPrint('FirebaseMessaging.getToken() returned no token.');
    } else {
      if (FirebaseAuth.instance.currentUser?.uid == expectedUid) {
        await registerPushTokenForCurrentUser(token);
      }
    }
    // Keep notification reads lazy. The notification center loads when opened.

    pushTokenRefreshSubscription ??= messaging.onTokenRefresh.listen(
      (token) {
        debugPrint('FCM token refreshed.');
        unawaited(registerPushTokenForCurrentUser(token));
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('FCM token refresh listener failed: $error');
        debugPrint('$stack');
      },
    );

    foregroundPushSubscription ??= FirebaseMessaging.onMessage.listen(
      (message) {
        debugPrint(
          'Foreground push received. messageId=${message.messageId}, data=${message.data}',
        );
        unawaited(showForegroundSystemNotification(message));
        // Notification count is refreshed lazily when the notification center is opened.
      },
      onError: (Object error, StackTrace stack) {
        debugPrint('Foreground push listener failed: $error');
        debugPrint('$stack');
      },
    );
  } catch (error, stack) {
    if (pushInitializationUid == expectedUid) {
      pushInitializationUid = null;
      pushInitializationFuture = null;
    }
    debugPrint('Push initialization failed: $error');
    debugPrint('$stack');
  }
}
