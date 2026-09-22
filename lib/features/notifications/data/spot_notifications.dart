import 'package:ccs_app/features/spots/models/spot_owner.dart'
    show spotNotificationOwnerUid;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show userNotificationsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show boolFromFirebase, mapFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension, FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/community_notifications.dart'
    show communityPushRecipientUserIds;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show createUserNotification;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show userDataAllowsSpotCountry;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;
import 'package:ccs_app/shared/models/countries.dart'
    show spotCountryFromCityCountry;

Future<void> createSpotLikeNotification(CarSpot spot, String likeId) async {
  final ownerUid = spotNotificationOwnerUid(spot);
  await createUserNotification(
    userId: ownerUid,
    type: 'spot_like',
    title: 'Likes on my spots',
    body: '@${currentUser.username} liked ${spot.name}.',
    settingName: 'likeNotifications',
    notificationId: likeId.trim().isEmpty ? null : 'spot_like_$likeId',
    extra: {
      'spotId': spot.id.trim().isNotEmpty
          ? spot.id.trim()
          : spotReviewKey(spot),
      'spotReviewId': spotReviewKey(spot),
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
    },
  );
}

Future<void> createSpotCommentNotification(
  CarSpot spot,
  String reviewId,
  String comment,
) async {
  final ownerUid = spotNotificationOwnerUid(spot);
  await createUserNotification(
    userId: ownerUid,
    type: 'spot_comment',
    title: 'Comments',
    body: '@${currentUser.username} commented on ${spot.name}.',
    settingName: 'commentNotifications',
    notificationId: reviewId.trim().isEmpty ? null : 'spot_comment_$reviewId',
    extra: {
      'reviewId': reviewId,
      'spotId': spot.id.trim().isNotEmpty
          ? spot.id.trim()
          : spotReviewKey(spot),
      'spotReviewId': spotReviewKey(spot),
      'spotName': spot.name,
      'comment': comment.trim(),
      'cityCountry': spot.cityCountry,
    },
  );
}

Future<void> createSpotReviewUpdateNotification(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  if (status != SpotStatus.approved && status != SpotStatus.rejected) {
    return;
  }

  final ownerUid = spotNotificationOwnerUid(spot);
  final statusName = spotStatusName(status);
  final approved = status == SpotStatus.approved;
  final cleanReason = rejectionReason.trim();

  await createUserNotification(
    userId: ownerUid,
    type: 'spot_review_update',
    title: 'Spot review updates',
    body: approved
        ? '${spot.name} was approved.'
        : cleanReason.isEmpty
        ? '${spot.name} was rejected.'
        : '${spot.name} was rejected. Reason: $cleanReason',
    settingName: 'reviewNotifications',
    notificationId: spot.id.trim().isEmpty
        ? null
        : 'spot_review_${spot.id}_${statusName}_$ownerUid',
    extra: {
      'spotId': spot.id.trim().isEmpty ? spotReviewKey(spot) : spot.id.trim(),
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'status': statusName,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      if (cleanReason.isNotEmpty) 'rejectionReason': cleanReason,
    },
  );
}

Future<void> createNewSpotNotificationForUsers(CarSpot spot) async {
  if (spot.isGroupSpot) return;
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null || spot.status != SpotStatus.approved) {
    return;
  }

  final type = spot.isTemporary ? 'temporary_event' : 'new_spot';
  final title = spot.isTemporary ? 'Events' : 'New spots';
  final body = spot.isTemporary
      ? '${spot.name} event was added in ${spot.cityCountry}.'
      : '${spot.name} was added in ${spot.cityCountry}.';
  final spotCountry = spotCountryFromCityCountry(spot.cityCountry);

  try {
    final usersSnapshot = await usersCollection()
        .limit(500)
        .debugGet(null, 'notifications: candidate users for new spot');
    final batch = FirebaseFirestore.instance.batch();
    var writes = 0;

    for (final doc in usersSnapshot.docs) {
      final userId = doc.id;
      final data = doc.data();
      if (userId == firebaseUser.uid || data['deleted'] == true) {
        continue;
      }

      final nestedSettings = mapFromFirebase(data['settings']);
      final enabled = data['newSpotNotifications'] is bool
          ? data['newSpotNotifications'] == true
          : boolFromFirebase(nestedSettings['newSpotNotifications'], true);
      if (!enabled) {
        continue;
      }
      if (!userDataAllowsSpotCountry(data, spotCountry)) {
        continue;
      }

      final notificationId = '${type}_${spot.id}_$userId';
      batch.debugSet(userNotificationsCollection().doc(notificationId), {
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'actorUserId': firebaseUser.uid,
        'actorUsername': currentUser.username,
        'spotId': spot.id,
        'spotName': spot.name,
        'cityCountry': spot.cityCountry,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;

      if (writes >= 450) {
        break;
      }
    }

    if (writes > 0) {
      await batch.debugCommit();
    }
  } catch (error, stack) {
    debugPrint('Could not create new spot notifications: $error');
    debugPrint('$stack');
  }
}

Future<void> sendNewSpotPushToEligibleUsers(CarSpot spot) async {
  if (spot.isGroupSpot) {
    await sendPushNotificationEvent({
      'type': 'temporary_event',
      'spotId': spot.id,
    });
    return;
  }
  final recipients = await communityPushRecipientUserIds(
    preferenceKey: 'newSpotNotifications',
    spotCountry: spotCountryFromCityCountry(spot.cityCountry),
  );
  if (recipients == null || recipients.isEmpty) {
    return;
  }

  await sendPushNotificationEvent({
    'type': spot.isTemporary ? 'temporary_event' : 'new_spot',
    'preferenceKey': 'newSpotNotifications',
    'notificationId':
        '${spot.isTemporary ? 'temporary_event' : 'new_spot'}_${spot.id}',
    'spotId': spot.id,
    'spotName': spot.name,
    'cityCountry': spot.cityCountry,
    'recipientUserIds': recipients,
    'preferencesAlreadyFiltered': true,
  });
}
