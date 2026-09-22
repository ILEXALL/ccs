import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugCollectionReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/moderation/data/forum_review_lease.dart'
    show ForumReviewLease;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;

Future<void> createForumReviewNotification({
  required Map<String, dynamic> topic,
  required String topicId,
  required String status,
  String rejectionReason = '',
}) async {
  final authorId = stringFromFirebase(topic['authorId'], '');
  final topicTitle = stringFromFirebase(topic['title'], 'Тема форума');

  if (authorId.trim().isEmpty) {
    return;
  }

  final title = status == 'approved'
      ? 'Тема форума одобрена'
      : 'Тема форума отклонена';
  final body = status == 'approved'
      ? 'Твоя тема "$topicTitle" одобрена и опубликована!'
      : 'Тема "$topicTitle" отклонена. Причина: ${rejectionReason.trim()}';

  try {
    await userNotificationsCollection().debugAdd({
      'userId': authorId,
      'type': 'forum_reviewed',
      'topicId': topicId,
      'actorUserId': currentUser.uid,
      'status': status,
      'title': title,
      'body': body,
      'topicTitle': topicTitle,
      'rejectionReason': status == 'rejected' ? rejectionReason.trim() : null,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (error, stack) {
    debugPrint('Could not create forum review notification: $error');
    debugPrint('$stack');
  }
}

Future<void> approveForumTopic(String topicId, ForumReviewLease lease) async {
  await lease.ensureActive();
  final result = await sendModerationAction({
    'action': 'forum_review',
    'operation': 'decide',
    'sessionId': lease.sessionId,
    'topicId': topicId,
    'status': 'approved',
  });
  lease.checkBlocked(result);
  // Publication is queued and dispatched by the committed backend decision.
  forumTopicsRefreshTick.value++;
  await lease.renew();
}

Future<void> rejectForumTopic(
  String topicId,
  String reason,
  ForumReviewLease lease,
) async {
  await lease.ensureActive();
  final result = await sendModerationAction({
    'action': 'forum_review',
    'operation': 'decide',
    'sessionId': lease.sessionId,
    'topicId': topicId,
    'status': 'rejected',
    'rejectionReason': reason.trim(),
  });
  lease.checkBlocked(result);
  await lease.renew();
  forumTopicsRefreshTick.value++;
}
