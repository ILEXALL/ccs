import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show adminNotificationsCollection, userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/moderation/data/staff_recipients.dart'
    show
        communityModerationUserIdsExcept,
        spotReviewStaffUserIdsExcept,
        staffUserIdsExcept;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show trySendPushNotificationEvent;
import 'package:ccs_app/features/profile/models/public_profile.dart'
    show PublicUserProfileData;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;

Future<void> notifyStaffAboutCommunityEvent({
  required String type,
  required String notificationId,
  required String title,
  required String body,
  Map<String, Object?> extra = const <String, Object?>{},
  bool sendPush = true,
  bool resolveRecipientsOnServer = false,
}) async {
  final senderUid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  final recipientUids = resolveRecipientsOnServer
      ? const <String>[]
      : await communityModerationUserIdsExcept(
          excludedUid: senderUid,
          countryCode: stringFromFirebase(extra['countryCode'], ''),
        );
  if (recipientUids.isEmpty && !resolveRecipientsOnServer) {
    debugPrint(
      'Community moderation notification skipped because no recipients were found.',
    );
    return;
  }

  if (recipientUids.isNotEmpty) {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final recipientUid in recipientUids) {
        batch.debugSet(
          adminNotificationsCollection().doc('${notificationId}_$recipientUid'),
          {
            'userId': recipientUid,
            'type': type,
            'title': title,
            'body': body,
            'actorUserId': senderUid,
            'actorUsername': currentUser.username,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMillis': nowMillis,
            ...extra,
          },
          SetOptions(merge: true),
          'admin notifications: community event',
        );
      }
      await batch.debugCommit();
    } catch (error, stack) {
      // The push endpoint may still be able to deliver even when client rules do
      // not permit direct writes to admin_notifications.
      debugPrint('Community admin notification documents failed: $error');
      debugPrint('$stack');
    }
  }

  if (!sendPush) {
    return;
  }

  final delivered = await trySendPushNotificationEvent({
    'type': type,
    'notificationId': notificationId,
    if (recipientUids.isNotEmpty) 'recipientUserIds': recipientUids,
    'title': title,
    'body': body,
    ...extra,
  });
  if (!delivered) {
    debugPrint('Community moderation push was not delivered: $notificationId');
  }
}

Future<void> createAdminUserReportNotifications({
  required String reportId,
  required PublicUserProfileData reportedUser,
  required String reporterUid,
  required String reporterUsername,
  required String reason,
  required int createdAtMillis,
}) async {
  if (reportId.trim().isEmpty || reportedUser.uid.trim().isEmpty) {
    return;
  }

  final staffUids = await staffUserIdsExcept(
    excludedUid: reporterUid,
    countryCode: countryIsoCode(reportedUser.country) ?? '',
  );
  if (staffUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();
  final cleanReporter = displayUsername(reporterUsername);
  final cleanReported = displayUsername(reportedUser.username);
  final cleanReason = reason.trim();

  for (final staffUid in staffUids) {
    final notificationId = 'user_report_${reportId}_$staffUid';
    batch.debugSet(adminNotificationsCollection().doc(notificationId), {
      'userId': staffUid,
      'type': 'user_report_new',
      'countryCode': countryIsoCode(reportedUser.country) ?? '',
      'title': 'New user report',
      'body':
          '$cleanReporter reported $cleanReported${cleanReason.isEmpty ? '.' : ': $cleanReason'}',
      'actorUserId': reporterUid,
      'actorUsername': reporterUsername,
      'reportedUid': reportedUser.uid,
      'reportedUsername': reportedUser.username,
      'reportId': reportId,
      'reason': cleanReason,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMillis': createdAtMillis,
    }, SetOptions(merge: true));
  }

  await batch.debugCommit();
}

Future<void> createAdminSpotReviewNotification(CarSpot spot) async {
  if (spot.id.trim().isEmpty || spot.status != SpotStatus.pending) {
    return;
  }

  final staffUids = await spotReviewStaffUserIdsExcept(
    spot,
    excludedUid: spot.addedByUid,
  );

  if (staffUids.isEmpty) {
    return;
  }

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  try {
    final batch = FirebaseFirestore.instance.batch();

    for (final staffUid in staffUids) {
      final notificationId = 'admin_${spot.id}_review_$staffUid';
      final notificationData = {
        'userId': staffUid,
        'type': 'spot_pending_review',
        'title': 'Spot review updates',
        'body': '${spot.name} is waiting for review.',
        'actorUserId': spot.addedByUid,
        'actorUsername': spot.addedBy,
        'spotId': spot.id,
        'spotName': spot.name,
        'cityCountry': spot.cityCountry,
        'countryCode': spot.effectiveCountryCode,
        'addedBy': spot.addedBy,
        'addedByUid': spot.addedByUid,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMillis': nowMillis,
      };

      batch.debugSet(
        adminNotificationsCollection().doc(notificationId),
        notificationData,
        SetOptions(merge: true),
      );
    }

    await batch.debugCommit();
  } catch (error, stack) {
    debugPrint('Pending spot admin notification documents failed: $error');
    debugPrint('$stack');
  }

  final delivered = await trySendPushNotificationEvent({
    'type': 'spot_pending_review',
    'notificationId': 'spot_pending_review_${spot.id}',
    'spotId': spot.id,
    'spotName': spot.name,
    'cityCountry': spot.cityCountry,
    'countryCode': spot.effectiveCountryCode,
    'addedBy': spot.addedBy,
    'addedByUid': spot.addedByUid,
    'recipientUserIds': staffUids,
    'title': 'Spot waiting for review',
    'body': '${spot.name} was submitted by @${spot.addedBy}.',
  });
  if (!delivered) {
    debugPrint('Pending spot admin push was not delivered: ${spot.id}');
  }
}

Future<void> createAdminSpotEditReviewNotification(CarSpot spot) async {
  if (spot.id.trim().isEmpty ||
      spot.status != SpotStatus.edited ||
      FirebaseAuth.instance.currentUser?.uid != spot.addedByUid) {
    return;
  }
  // The authenticated server chooses eligible staff and owns both the bell
  // entry and push. Its saved editedAt revision deduplicates endpoint retries.
  final delivered = await trySendPushNotificationEvent({
    'type': 'spot_pending_review',
    'reviewKind': 'edited',
    'spotId': spot.id,
    'notificationId': 'spot_edit_review_${spot.id}_${spot.updatedAtMillis}',
  });
  if (!delivered) {
    debugPrint('Edited spot review notification dispatch failed: ${spot.id}');
  }
}

Future<void> createAdminSpotDecisionNotification(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  if (spot.id.trim().isEmpty ||
      (status != SpotStatus.approved && status != SpotStatus.rejected)) {
    return;
  }

  final adminUids = await spotReviewStaffUserIdsExcept(
    spot,
    excludedUid: currentUser.uid,
  );

  if (adminUids.isEmpty) {
    return;
  }

  final batch = FirebaseFirestore.instance.batch();
  final statusName = spotStatusName(status);
  final cleanReason = rejectionReason.trim();

  for (final adminUid in adminUids) {
    final notificationRef = userNotificationsCollection().doc(
      'admin_${spot.id}_${statusName}_$adminUid',
    );
    batch.debugSet(notificationRef, {
      'userId': adminUid,
      'type': status == SpotStatus.approved
          ? 'spot_approved_by_admin'
          : 'spot_rejected_by_admin',
      'title': 'Spot review updates',
      'body': status == SpotStatus.approved
          ? '${spot.name} approved by ${currentUser.username}.'
          : cleanReason.isEmpty
          ? '${spot.name} rejected by ${currentUser.username}.'
          : '${spot.name} rejected by ${currentUser.username}. Reason: $cleanReason',
      'actorUserId': currentUser.uid,
      'actorUsername': currentUser.username,
      'spotId': spot.id,
      'spotName': spot.name,
      'cityCountry': spot.cityCountry,
      'countryCode': spot.effectiveCountryCode,
      'status': statusName,
      'reviewedBy': currentUser.username,
      'reviewedByUid': currentUser.uid,
      if (cleanReason.isNotEmpty) 'rejectionReason': cleanReason,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  await batch.debugCommit();
}
