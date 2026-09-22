import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/network/in_flight_load.dart';
import 'package:ccs_app/core/config/app_config.dart' show pushNotificationUrl;
import 'package:ccs_app/core/firestore/collections.dart'
    show
        adminNotificationsCollection,
        friendLocationNotificationsCollection,
        spotsCollection,
        userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase, timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/core/network/json_http.dart' show patchJsonToUrl;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show moderationNotificationAllowed;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show notificationCenterUnreadCount, notificationCenterUnreadCountsBySource;
import 'package:ccs_app/features/notifications/data/notification_deduplication.dart'
    show
        removeDuplicateActionNotifications,
        removeDuplicatePublicSpotNotifications,
        removeDuplicateSpotReviewNotifications;
import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show
        actorUsernameFromNotificationBody,
        bodyWithRejectionReason,
        chatNotificationTitle,
        notificationCenterItemIsRejected,
        notificationCenterItemIsSelfAuthoredMessage,
        spotNameFromNotificationBody;
import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show chatIdFromNotificationItem;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show userSettings;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, submittedSpots;

Future<void> markNotificationReadBestEffort(
  DocumentReference<Map<String, dynamic>> reference,
) async {
  try {
    await reference.debugSet({'read': true}, SetOptions(merge: true));
  } catch (error) {
    // Some rules do not allow clients to update notification documents. Opening
    // the notification must still work, so treat this as cosmetic only.
    debugPrint('Notification read mark skipped: $error');
  }
}

NotificationCenterItem notificationCenterItemFromJson(Object? value) {
  final data = mapFromFirebase(value);
  final payload = mapFromFirebase(data['data']);

  String pickString(String key, String fallback) {
    final topLevel = stringFromFirebase(data[key], '');
    if (topLevel.trim().isNotEmpty) {
      return topLevel;
    }
    return stringFromFirebase(payload[key], fallback);
  }

  int pickMillis(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.toInt();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.toInt();
    }
    return 0;
  }

  int pickInt(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.round();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.round();
    }
    return 0;
  }

  double pickDouble(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.toDouble();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.toDouble();
    }
    return 0;
  }

  final type = pickString('type', 'notification');
  final status = pickString('status', '');
  final rawSpotName = pickString('spotName', '');
  final rejectionReason = pickString('rejectionReason', '');
  var body = pickString('body', '');
  final spotName = rawSpotName.trim().isNotEmpty
      ? rawSpotName
      : spotNameFromNotificationBody(type, body);
  final rawActorUsername = pickString(
    'actorUsername',
    pickString('senderUsername', pickString('fromUsername', '')),
  );
  final actorUsername = rawActorUsername.trim().isEmpty
      ? actorUsernameFromNotificationBody(body)
      : rawActorUsername;
  final actorUserId = pickString(
    'actorUserId',
    pickString(
      'senderUid',
      pickString('senderUserId', pickString('fromUid', '')),
    ),
  );

  if (type == 'spot_review_update' &&
      status == 'rejected' &&
      rejectionReason.trim().isNotEmpty &&
      !body.toLowerCase().contains('reason:')) {
    final lowerBody = body.toLowerCase();
    if (body.trim().isEmpty || lowerBody.contains('not approved')) {
      body = spotName.trim().isEmpty
          ? 'Your spot was rejected. Reason: ${rejectionReason.trim()}'
          : '$spotName was rejected. Reason: ${rejectionReason.trim()}';
    } else if (lowerBody.contains('rejected')) {
      body = bodyWithRejectionReason(body, rejectionReason);
    }
  }

  return NotificationCenterItem(
    id: pickString('id', ''),
    title: pickString('title', 'CCS'),
    body: body,
    type: type,
    createdAtMillis: pickMillis('createdAtMillis'),
    read: data['read'] == true || payload['read'] == true,
    projectNews: data['projectNews'] == true || payload['projectNews'] == true,
    spotId: pickString('spotId', ''),
    spotName: spotName,
    chatId: (() {
      final v = pickString('chatId', '');
      if (v.isNotEmpty) return v;
      return pickString('chat_id', '');
    })(),
    topicId: pickString('topicId', ''),
    countryCode: pickString('countryCode', ''),
    reviewId: pickString('reviewId', ''),
    messageId: pickString('messageId', ''),
    likeId: pickString('likeId', ''),
    userId: pickString('userId', ''),
    addedByUid: pickString('addedByUid', ''),
    actorUserId: actorUserId,
    actorUsername: actorUsername,
    friendLat: pickDouble('friendLat'),
    friendLng: pickDouble('friendLng'),
    status: status,
    rejectionReason: rejectionReason,
    xpAmount: pickInt('xpAmount'),
    xpAction: pickString('xpAction', ''),
    xpTransactionId: pickString('xpTransactionId', ''),
  );
}

NotificationCenterItem notificationCenterItemFromDocument(
  DocumentSnapshot<Map<String, dynamic>> doc, {
  bool projectNews = false,
}) {
  final data = doc.data() ?? {};
  final payload = mapFromFirebase(data['data']);

  String pickString(String key, String fallback) {
    final topLevel = stringFromFirebase(data[key], '');
    if (topLevel.trim().isNotEmpty) {
      return topLevel;
    }
    return stringFromFirebase(payload[key], fallback);
  }

  double pickDouble(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.toDouble();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.toDouble();
    }
    return 0;
  }

  int pickInt(String key) {
    final topLevel = data[key];
    if (topLevel is num) {
      return topLevel.round();
    }
    final nested = payload[key];
    if (nested is num) {
      return nested.round();
    }
    return 0;
  }

  final type = pickString(
    'type',
    projectNews ? 'project_news' : 'notification',
  );
  final rawSpotName = pickString('spotName', '');
  final status = pickString('status', '');
  final reviewedBy = pickString('reviewedBy', '');
  final rejectionReason = pickString('rejectionReason', '');
  final actorUsername = pickString(
    'actorUsername',
    pickString('senderUsername', ''),
  );
  final actorUserId = pickString('actorUserId', pickString('senderUid', ''));
  final comment = pickString('comment', '');
  final friendUsername = pickString('friendUsername', '');
  // Always use the canonical title for each type — ignore whatever Firebase stored.
  final title = pickString('notificationKind', '') == 'mention'
      ? 'You were mentioned'
      : switch (type) {
          'spot_like' => 'Likes on my spots',
          'spot_comment' => 'Comments',
          'spot_review_update' => 'Spot review updates',
          'chat_message' => chatNotificationTitle(actorUsername),
          'new_spot' => 'New spots',
          'temporary_event' => 'Events',
          'temporary_spot_today' => 'Event starts in 5 hours',
          'global_chat_message' || 'global_chat_admin' => 'Global chat',
          'forum_topic_created' => pickString('title', 'New forum topic'),
          'forum_reply' => pickString('title', 'Forum'),
          'forum_topic_pending' => 'Forum topic waiting for review',
          'forum_reply_admin' => 'New forum reply',
          'spot_pending_review' =>
            pickString('reviewKind', '') == 'edited'
                ? 'Spot edited — approval required'
                : 'Spot review updates',
          'user_report_new' => 'New user report',
          'spot_removal_request' => 'Spot removal request',
          'spot_approved_by_admin' ||
          'spot_rejected_by_admin' => 'Spot review updates',
          'friend_request' => 'New friend request',
          'friend_nearby' ||
          'friend_at_spot' ||
          'friend_live_sharing' => 'Live location',
          'xp_reward' => 'XP reward',
          'project_news' => 'Project news',
          _ => stringFromFirebase(data['title'], 'CCS'),
        };
  var body = pickString('body', '');
  final spotName = rawSpotName.trim().isNotEmpty
      ? rawSpotName
      : spotNameFromNotificationBody(type, body);

  if (body.trim().isEmpty) {
    body = switch (type) {
      'spot_like' =>
        spotName.trim().isEmpty
            ? '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} liked your spot.'
            : '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} liked $spotName.',
      'spot_comment' =>
        spotName.trim().isEmpty
            ? '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} commented on your spot${comment.trim().isEmpty ? '.' : ': $comment'}'
            : '${actorUsername.trim().isEmpty ? 'Someone' : '@$actorUsername'} commented on $spotName${comment.trim().isEmpty ? '.' : ': $comment'}',
      'chat_message' =>
        actorUsername.trim().isEmpty
            ? 'New message.'
            : '@$actorUsername: New message.',
      'new_spot' =>
        spotName.trim().isEmpty
            ? 'New spot was added.'
            : '$spotName was added.',
      'temporary_event' =>
        spotName.trim().isEmpty
            ? 'New event was added.'
            : '$spotName event was added.',
      'temporary_spot_today' =>
        spotName.trim().isEmpty
            ? 'A event starts in about 5 hours.'
            : '$spotName starts in about 5 hours.',
      'global_chat_message' ||
      'global_chat_admin' => 'New message in global chat.',
      'forum_topic_created' => 'A new forum topic was created.',
      'forum_reply' => 'A new reply was posted in the forum.',
      'forum_topic_pending' => 'A forum topic is waiting for review.',
      'forum_reply_admin' => 'A new reply was posted in the forum.',
      'spot_review_update' =>
        status == 'approved'
            ? (spotName.trim().isEmpty
                  ? 'Your spot was approved.'
                  : '$spotName was approved.')
            : (spotName.trim().isEmpty
                  ? 'Your spot was rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'
                  : '$spotName was rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'),
      'spot_pending_review' =>
        spotName.trim().isEmpty
            ? 'New spot is waiting for review.'
            : '$spotName is waiting for review.',
      'user_report_new' =>
        body.trim().isNotEmpty ? body : 'A user report is waiting for review.',
      'spot_approved_by_admin' =>
        spotName.trim().isEmpty
            ? 'Spot approved.'
            : '$spotName approved${reviewedBy.trim().isEmpty ? '' : ' by $reviewedBy'}.',
      'spot_rejected_by_admin' =>
        spotName.trim().isEmpty
            ? 'Spot rejected${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}'
            : '$spotName rejected${reviewedBy.trim().isEmpty ? '' : ' by $reviewedBy'}${rejectionReason.trim().isEmpty ? '.' : '. Reason: $rejectionReason'}',
      'friend_request' =>
        friendUsername.trim().isEmpty
            ? 'Someone sent you a friend request.'
            : '@$friendUsername sent you a friend request.',
      'friend_nearby' =>
        friendUsername.trim().isEmpty
            ? 'A friend is nearby.'
            : '@$friendUsername is nearby.',
      'friend_at_spot' =>
        friendUsername.trim().isEmpty
            ? 'A friend is at a spot.'
            : '@$friendUsername is at ${spotName.trim().isEmpty ? 'a spot' : spotName}.',
      'friend_live_sharing' =>
        friendUsername.trim().isEmpty
            ? 'A friend is sharing live location.'
            : '@$friendUsername is sharing live location.',
      'xp_reward' => 'XP reward',
      _ => pickString('message', ''),
    };
  }

  final cleanReason = rejectionReason.trim();
  final rejectedWithoutReason =
      cleanReason.isNotEmpty &&
      ((type == 'spot_review_update' && status == 'rejected') ||
          type == 'spot_rejected_by_admin') &&
      !body.toLowerCase().contains('reason:') &&
      body.toLowerCase().contains('rejected');
  if (rejectedWithoutReason) {
    body = bodyWithRejectionReason(body, cleanReason);
  }

  return NotificationCenterItem(
    id: doc.id,
    title: title,
    body: body,
    type: type,
    createdAtMillis: timestampMillisFromFirebase(data['createdAt']),
    read: data['read'] == true,
    reference: projectNews ? null : doc.reference,
    projectNews: projectNews,
    spotId: (() {
      final v = pickString('spotId', '');
      if (v.trim().isNotEmpty) return v;
      final alt = pickString('spot_id', '');
      if (alt.trim().isNotEmpty) return alt;
      return pickString('spotReviewId', '');
    })(),
    spotName: spotName,
    chatId: (() {
      final v = pickString('chatId', '');
      if (v.isNotEmpty) return v;
      return pickString('chat_id', '');
    })(),
    topicId: pickString('topicId', ''),
    countryCode: pickString('countryCode', ''),
    reviewId: pickString('reviewId', ''),
    messageId: pickString('messageId', ''),
    likeId: pickString('likeId', ''),
    userId: pickString('userId', ''),
    addedByUid: pickString('addedByUid', ''),
    actorUserId: actorUserId,
    actorUsername: actorUsername.trim().isEmpty
        ? actorUsernameFromNotificationBody(body)
        : actorUsername,
    friendLat: pickDouble('friendLat'),
    friendLng: pickDouble('friendLng'),
    status: status,
    rejectionReason: rejectionReason,
    xpAmount: pickInt('xpAmount'),
    xpAction: pickString('xpAction', ''),
    xpTransactionId: pickString('xpTransactionId', ''),
  );
}

String notificationCenterHiddenIdsKey(String uid) =>
    'notification_center_hidden_ids_$uid';

Future<Set<String>> loadHiddenNotificationCenterIds(String uid) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(notificationCenterHiddenIdsKey(uid))?.toSet() ??
        <String>{};
  } catch (_) {
    return <String>{};
  }
}

Future<void> saveHiddenNotificationCenterIds(
  String uid,
  Set<String> ids,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      notificationCenterHiddenIdsKey(uid),
      ids.toList(),
    );
  } catch (_) {}
}

Future<String> rejectionReasonForNotificationItem(
  NotificationCenterItem item,
) async {
  final existingReason = item.rejectionReason.trim();
  if (existingReason.isNotEmpty) {
    return existingReason;
  }

  final cleanSpotId = item.spotId.trim();
  if (cleanSpotId.isEmpty) {
    return '';
  }

  for (final spot in [
    ...reviewSpots.value,
    ...submittedSpots.value,
    ...approvedPublicSpots(),
  ]) {
    if (spot.id == cleanSpotId || spotReviewKey(spot) == cleanSpotId) {
      return spot.rejectionReason.trim();
    }
  }

  try {
    final doc = await spotsCollection().doc(cleanSpotId).debugGet();
    if (!doc.exists) {
      return '';
    }
    final data = doc.data() ?? {};
    return stringFromFirebase(data['rejectionReason'], '').trim();
  } catch (error, stack) {
    debugPrint('Could not load rejection reason for notification: $error');
    debugPrint('$stack');
    return '';
  }
}

Future<List<NotificationCenterItem>> enrichRejectedNotificationCenterItems(
  List<NotificationCenterItem> items,
) async {
  final enriched = <NotificationCenterItem>[];

  for (final item in items) {
    if (!notificationCenterItemIsRejected(item)) {
      enriched.add(item);
      continue;
    }

    final reason = await rejectionReasonForNotificationItem(item);
    if (reason.trim().isEmpty) {
      enriched.add(item);
      continue;
    }

    enriched.add(
      item.copyWith(
        status: item.status.trim().isEmpty ? 'rejected' : item.status,
        rejectionReason: reason.trim(),
        body: bodyWithRejectionReason(item.body, reason),
      ),
    );
  }

  return enriched;
}

Future<Map<String, String>?> firebaseNotificationHeaders() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return null;
  }

  final token = await firebaseUser.getIdToken();
  if (token == null || token.trim().isEmpty) {
    return null;
  }

  return {HttpHeaders.authorizationHeader: 'Bearer $token'};
}

Future<QuerySnapshot<Map<String, dynamic>>> loadNotificationCenterSnapshot(
  CollectionReference<Map<String, dynamic>> collection,
  String uid,
  String label,
) async {
  final query = collection
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(25);

  try {
    return await query.debugGet(null, 'notification center: $label');
  } catch (error, stack) {
    debugPrint(
      'Ordered notification query failed for $label, retrying without order: $error',
    );
    debugPrint('$stack');
    return collection
        .where('userId', isEqualTo: uid)
        .limit(25)
        .debugGet(null, 'notification center: $label fallback');
  }
}

Future<QuerySnapshot<Map<String, dynamic>>> loadUserNotificationCenterSnapshot(
  String uid,
) {
  return loadNotificationCenterSnapshot(
    userNotificationsCollection(),
    uid,
    'user notifications',
  );
}

const int maxVisibleNotificationCenterItems = 9;

Future<void> pruneOldNotificationCenterItems(
  String uid,
  List<NotificationCenterItem> sortedItems,
) async {
  final visibleItems = sortedItems.where((item) => !item.projectNews).toList();
  if (visibleItems.length <= maxVisibleNotificationCenterItems) {
    return;
  }

  final oldItems = visibleItems
      .skip(maxVisibleNotificationCenterItems)
      .toList();
  final references = oldItems
      .map((item) => item.reference)
      .whereType<DocumentReference<Map<String, dynamic>>>()
      .toList();

  if (references.isNotEmpty) {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final reference in references) {
        batch.debugDelete(reference);
      }
      await batch.debugCommit();
    } catch (error, stack) {
      debugPrint('Notification center old-item pruning failed: $error');
      debugPrint('$stack');
    }
  }

  final serverOnlyIds = oldItems
      .where((item) => item.reference == null && !item.projectNews)
      .map((item) => item.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (serverOnlyIds.isNotEmpty) {
    final hiddenIds = await loadHiddenNotificationCenterIds(uid);
    hiddenIds.addAll(serverOnlyIds);
    await saveHiddenNotificationCenterIds(uid, hiddenIds);
  }
}

final _notificationCenterLoads =
    InFlightLoad<String, List<NotificationCenterItem>>();

Future<List<NotificationCenterItem>> loadNotificationCenterItems() {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return _notificationCenterLoads.run(uid, _loadNotificationCenterItems);
}

Future<List<NotificationCenterItem>> _loadNotificationCenterItems() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final items = <NotificationCenterItem>[];

  if (firebaseUser == null) {
    notificationCenterUnreadCountsBySource.clear();
    notificationCenterUnreadCount.value = 0;
    return const [];
  }

  Future<void> loadFromCollection(
    CollectionReference<Map<String, dynamic>> collection,
    String label,
  ) async {
    try {
      final snapshot = await loadNotificationCenterSnapshot(
        collection,
        firebaseUser.uid,
        label,
      );
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (!moderationNotificationAllowed(data)) continue;
        items.add(notificationCenterItemFromDocument(doc));
      }
    } catch (error, stack) {
      debugPrint('Notification center could not load $label: $error');
      debugPrint('$stack');
    }
  }

  await loadFromCollection(userNotificationsCollection(), 'user notifications');
  await loadFromCollection(
    adminNotificationsCollection(),
    'admin notifications',
  );
  await loadFromCollection(
    friendLocationNotificationsCollection(),
    'friend location notifications',
  );

  if (!userSettings.value.xpNotifications) {
    items.removeWhere((item) => item.type == 'xp_reward');
  }

  final uniqueItemsById = <String, NotificationCenterItem>{};
  final uniqueItemsWithoutId = <NotificationCenterItem>[];
  for (final item in items) {
    final id = item.id.trim();
    if (id.isEmpty) {
      uniqueItemsWithoutId.add(item);
      continue;
    }

    final existing = uniqueItemsById[id];
    if (existing == null ||
        item.createdAtMillis >= existing.createdAtMillis ||
        item.reference?.path.startsWith('admin_notifications/') == true) {
      uniqueItemsById[id] = item;
    }
  }
  items
    ..clear()
    ..addAll(uniqueItemsById.values)
    ..addAll(uniqueItemsWithoutId);

  // User-facing action notifications need a real target. Old push/history
  // copies can have only title/body, which cannot open a chat or spot.
  items.removeWhere((item) {
    if (notificationCenterItemIsSelfAuthoredMessage(item, firebaseUser.uid)) {
      return true;
    }

    if (item.type == 'chat_message') {
      return chatIdFromNotificationItem(item).isEmpty;
    }

    if (item.type == 'spot_comment' || item.type == 'spot_like') {
      return item.reference == null &&
          item.spotId.trim().isEmpty &&
          spotNameFromNotificationBody(item.type, item.body).isEmpty;
    }

    return false;
  });

  if (!items.any((item) => item.projectNews)) {
    items.addAll(const [
      NotificationCenterItem(
        id: 'project_news_ready',
        title: 'Project news',
        body: 'CCS notification center is ready.',
        type: 'project_news',
        createdAtMillis: 0,
        read: true,
        projectNews: true,
      ),
    ]);
  }

  final hiddenIds = await loadHiddenNotificationCenterIds(firebaseUser.uid);
  if (hiddenIds.isNotEmpty) {
    items.removeWhere((item) {
      final id = item.id.trim();
      return id.isNotEmpty && hiddenIds.contains(id);
    });
  }

  final enrichedItems = removeDuplicateActionNotifications(
    removeDuplicatePublicSpotNotifications(
      removeDuplicateSpotReviewNotifications(
        await enrichRejectedNotificationCenterItems(items),
      ),
    ),
  );
  items
    ..clear()
    ..addAll(enrichedItems);

  items.sort((first, second) {
    if (first.createdAtMillis == second.createdAtMillis) {
      return first.projectNews ? 1 : -1;
    }

    return second.createdAtMillis.compareTo(first.createdAtMillis);
  });

  // A request started before logout must not update the next account's badge.
  if (FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid)
    return const [];
  await pruneOldNotificationCenterItems(firebaseUser.uid, items);

  final realItems = items.where((item) => !item.projectNews).toList();
  final projectItems = items.where((item) => item.projectNews).toList();
  final visibleItems = <NotificationCenterItem>[
    ...realItems.take(maxVisibleNotificationCenterItems),
  ];
  if (visibleItems.isEmpty && projectItems.isNotEmpty) {
    visibleItems.add(projectItems.first);
  } else if (visibleItems.length < maxVisibleNotificationCenterItems &&
      projectItems.isNotEmpty) {
    visibleItems.add(projectItems.first);
  }
  visibleItems.sort((first, second) {
    if (first.createdAtMillis == second.createdAtMillis) {
      return first.projectNews ? 1 : -1;
    }
    return second.createdAtMillis.compareTo(first.createdAtMillis);
  });

  if (FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid)
    return const [];
  notificationCenterUnreadCount.value = visibleItems
      .where((item) => !item.read && !item.projectNews)
      .length;
  return visibleItems.take(maxVisibleNotificationCenterItems).toList();
}

Future<void> markNotificationCenterItemsRead(
  Iterable<NotificationCenterItem> items,
) async {
  final unreadItems = items.where((item) => !item.read).toList();
  final firestoreItems = unreadItems
      .where((item) => !item.read && item.reference != null)
      .toList();
  final serverNotificationIds = unreadItems
      .where((item) => item.reference == null && !item.projectNews)
      .map((item) => item.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (firestoreItems.isEmpty && serverNotificationIds.isEmpty) {
    return;
  }

  try {
    if (serverNotificationIds.isNotEmpty) {
      final headers = await firebaseNotificationHeaders();
      if (headers != null) {
        await patchJsonToUrl(pushNotificationUrl, {
          'notificationIds': serverNotificationIds,
        }, headers: headers);
      }
    }

    if (firestoreItems.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in firestoreItems) {
        final reference = item.reference;
        if (reference == null) {
          continue;
        }
        batch.debugSet(reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.debugCommit();
    }

    notificationCenterUnreadCount.value = 0;
  } catch (error, stack) {
    debugPrint('Notification history could not be marked read: $error');
    debugPrint('$stack');
  }
}

Future<void> clearNotificationCenterItems(
  Iterable<NotificationCenterItem> items,
) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    notificationCenterUnreadCountsBySource.clear();
    notificationCenterUnreadCount.value = 0;
    return;
  }

  final cleanItems = items.toList();
  if (cleanItems.isEmpty) {
    notificationCenterUnreadCountsBySource.clear();
    notificationCenterUnreadCount.value = 0;
    return;
  }

  final hiddenIds = await loadHiddenNotificationCenterIds(firebaseUser.uid);
  for (final item in cleanItems) {
    final id = item.id.trim();
    if (id.isNotEmpty) {
      hiddenIds.add(id);
    }
  }
  await saveHiddenNotificationCenterIds(firebaseUser.uid, hiddenIds);

  final references = cleanItems
      .map((item) => item.reference)
      .whereType<DocumentReference<Map<String, dynamic>>>()
      .toList();

  if (references.isNotEmpty) {
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final reference in references) {
        batch.debugDelete(reference);
      }
      await batch.debugCommit();
    } catch (error, stack) {
      debugPrint('Notification center could not clear Firestore items: $error');
      debugPrint('$stack');
    }
  }

  final serverNotificationIds = cleanItems
      .where((item) => item.reference == null && !item.projectNews)
      .map((item) => item.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  if (serverNotificationIds.isNotEmpty) {
    try {
      final headers = await firebaseNotificationHeaders();
      if (headers != null) {
        // The backend currently supports marking notifications read. The local
        // hidden-id list above keeps cleared server-history items out of the
        // bell even if the backend does not physically delete them yet.
        await patchJsonToUrl(pushNotificationUrl, {
          'notificationIds': serverNotificationIds,
        }, headers: headers);
      }
    } catch (error, stack) {
      debugPrint(
        'Server notifications could not be marked read while clearing: $error',
      );
      debugPrint('$stack');
    }
  }

  notificationCenterUnreadCountsBySource.clear();
  notificationCenterUnreadCount.value = 0;
}

Future<void> refreshNotificationCenterUnreadCount() async {
  await loadNotificationCenterItems();
}
