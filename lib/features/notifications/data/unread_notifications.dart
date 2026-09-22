import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/notifications/models/notification_freshness.dart';
import 'package:ccs_app/features/progression/controllers/reward_feedback.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show
        adminNotificationsCollection,
        friendLocationNotificationsCollection,
        userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugQueryExtension,
        FirestoreDebugWriteBatchExtension,
        trackedQuerySnapshots;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show
        chatUnreadCountsByChatId,
        notificationCenterUnreadCount,
        notificationCenterUnreadCountsBySource;
import 'package:ccs_app/features/notifications/data/notification_repository.dart'
    show refreshNotificationCenterUnreadCount;

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
notificationCenterUnreadSubscription;

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
adminNotificationCenterUnreadSubscription;

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
friendLocationNotificationCenterUnreadSubscription;

Timer? notificationCenterUnreadRefreshDebounce;

int totalChatUnreadCount(Map<String, int> countsByChatId) {
  var total = 0;
  for (final count in countsByChatId.values) {
    if (count > 0) {
      total += count;
    }
  }
  return total;
}

String chatIdFromNotificationData(
  Map<String, dynamic> data,
  String notificationId,
  String currentUid,
) {
  final payload = mapFromFirebase(data['data']);

  String pickString(String key) {
    final topLevel = stringFromFirebase(data[key], '');
    if (topLevel.trim().isNotEmpty) {
      return topLevel.trim();
    }

    return stringFromFirebase(payload[key], '').trim();
  }

  final chatId = pickString('chatId');
  if (chatId.isNotEmpty) {
    return chatId;
  }

  final snakeChatId = pickString('chat_id');
  if (snakeChatId.isNotEmpty) {
    return snakeChatId;
  }

  if (currentUid.isNotEmpty && notificationId.startsWith('chat_')) {
    final match = RegExp(
      '^chat_(.+)_\\d+_${RegExp.escape(currentUid)}\$',
    ).firstMatch(notificationId);
    final parsedChatId = match?.group(1)?.trim() ?? '';
    if (parsedChatId.isNotEmpty) {
      return parsedChatId;
    }
  }

  return '';
}

void updateChatUnreadCountsFromNotificationDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String currentUid,
) {
  final counts = <String, int>{};

  for (final doc in docs) {
    final data = doc.data();
    if (data['read'] == true) {
      continue;
    }

    final type = stringFromFirebase(
      data['type'],
      stringFromFirebase(mapFromFirebase(data['data'])['type'], ''),
    );
    if (type != 'chat_message') {
      continue;
    }

    final notificationUserId = stringFromFirebase(data['userId'], currentUid);
    if (notificationUserId.trim().isNotEmpty &&
        notificationUserId.trim() != currentUid) {
      continue;
    }

    final chatId = chatIdFromNotificationData(data, doc.id, currentUid);
    if (chatId.isEmpty) {
      continue;
    }

    counts[chatId] = (counts[chatId] ?? 0) + 1;
  }

  chatUnreadCountsByChatId.value = counts;
}

Future<void> markChatNotificationsRead(String chatId) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final cleanChatId = chatId.trim();
  if (firebaseUser == null || cleanChatId.isEmpty) {
    return;
  }

  try {
    final snapshot = await userNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .where('read', isEqualTo: false)
        .limit(100)
        .debugGet(null, 'chat: mark unread notifications read');
    final references = <DocumentReference<Map<String, dynamic>>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = stringFromFirebase(
        data['type'],
        stringFromFirebase(mapFromFirebase(data['data'])['type'], ''),
      );
      if (type != 'chat_message') {
        continue;
      }

      if (chatIdFromNotificationData(data, doc.id, firebaseUser.uid) ==
          cleanChatId) {
        references.add(doc.reference);
      }
    }

    if (references.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final reference in references) {
        batch.debugSet(reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.debugCommit();
    }

    final nextCounts = Map<String, int>.from(chatUnreadCountsByChatId.value)
      ..remove(cleanChatId);
    chatUnreadCountsByChatId.value = nextCounts;
    scheduleNotificationCenterUnreadRefresh();
  } catch (error, stack) {
    debugPrint('Chat notifications could not be marked read: $error');
    debugPrint('$stack');
  }
}

void scheduleNotificationCenterUnreadRefresh({
  Duration delay = const Duration(milliseconds: 350),
}) {
  notificationCenterUnreadRefreshDebounce?.cancel();
  notificationCenterUnreadRefreshDebounce = Timer(delay, () {
    unawaited(refreshNotificationCenterUnreadCount());
  });
}

void startNotificationCenterUnreadWatcher() {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  notificationCenterUnreadRefreshDebounce?.cancel();
  notificationCenterUnreadRefreshDebounce = null;

  if (firebaseUser == null) {
    notificationCenterUnreadCountsBySource.clear();
    notificationCenterUnreadCount.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chatUnreadCountsByChatId.value = const <String, int>{};
    });
    return;
  }

  notificationCenterUnreadSubscription?.cancel();
  adminNotificationCenterUnreadSubscription?.cancel();
  friendLocationNotificationCenterUnreadSubscription?.cancel();
  notificationCenterUnreadCountsBySource.clear();
  notificationCenterUnreadCount.value = 0;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    chatUnreadCountsByChatId.value = const <String, int>{};
  });

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchUnreadQuery(
    String source,
    Query<Map<String, dynamic>> query,
  ) {
    bool initialized = false;
    final alertGate = NotificationFreshness(DateTime.now());
    return trackedQuerySnapshots(
      'notification center unread watcher: $source',
      query
          .where('read', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(50),
    ).listen(
      (snapshot) {
        if (initialized && !snapshot.metadata.isFromCache) {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data() ?? {};
            final rawCreated = data['createdAt'];
            final created = rawCreated is Timestamp
                ? rawCreated.toDate()
                : data['createdAtMillis'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (data['createdAtMillis'] as num).toInt(),
                  )
                : null;
            if (change.type == DocumentChangeType.added &&
                alertGate.accept(change.doc.id, created)) {
              handleRewardNotification(
                firebaseUser.uid,
                change.doc.id,
                change.doc.data() ?? {},
              );
            }
          }
        }
        if (!initialized) alertGate.seed(snapshot.docs.map((doc) => doc.id));
        if (!snapshot.metadata.isFromCache) initialized = true;
        // Do not trust raw unread counts for the bell. Older/hidden/invalid
        // notifications can still be unread in Firestore, while the
        // notification center filters them out. Recompute the visible unread
        // count through the same loader used by the notification screen.
        notificationCenterUnreadCountsBySource[source] = snapshot.docs.length;
        if (source == 'user') {
          updateChatUnreadCountsFromNotificationDocs(
            snapshot.docs,
            firebaseUser.uid,
          );
        }
        scheduleNotificationCenterUnreadRefresh();
      },
      onError: (Object error, StackTrace stack) {
        notificationCenterUnreadCountsBySource[source] = 0;
        if (source == 'user') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            chatUnreadCountsByChatId.value = const <String, int>{};
          });
        }
        scheduleNotificationCenterUnreadRefresh();
        debugPrint('Notification unread watcher failed ($source): $error');
        debugPrint('$stack');
      },
    );
  }

  notificationCenterUnreadSubscription = watchUnreadQuery(
    'user',
    userNotificationsCollection().where('userId', isEqualTo: firebaseUser.uid),
  );
  adminNotificationCenterUnreadSubscription = watchUnreadQuery(
    'admin',
    adminNotificationsCollection().where('userId', isEqualTo: firebaseUser.uid),
  );
  friendLocationNotificationCenterUnreadSubscription = watchUnreadQuery(
    'friendLocation',
    friendLocationNotificationsCollection().where(
      'userId',
      isEqualTo: firebaseUser.uid,
    ),
  );

  scheduleNotificationCenterUnreadRefresh(
    delay: const Duration(milliseconds: 50),
  );
}
