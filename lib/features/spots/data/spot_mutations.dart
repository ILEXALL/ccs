import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show updateTemporarySpotForumTopicAfterSpotReview;
import 'package:ccs_app/features/events/data/event_reminders.dart'
    show notifyAllUsersIfTemporarySpotIsToday;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/notifications/data/event_notifications.dart'
    show createMeetSpotNotificationsForNearbyUsers;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show createAdminSpotDecisionNotification;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/spot_notifications.dart'
    show
        createNewSpotNotificationForUsers,
        createSpotReviewUpdateNotification,
        sendNewSpotPushToEligibleUsers;
import 'package:ccs_app/features/spots/models/spot_owner.dart'
    show spotNotificationOwnerUid;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show syncXpWithServer;
import 'package:ccs_app/features/spots/data/saved_spots.dart'
    show saveSavedSpotIds;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show removeSpotFromLocalImmediateCache, upsertSpotIntoLocalImmediateCache;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;

Future<void> updateSpotStatus(
  CarSpot spot,
  SpotStatus status, {
  required String reviewSessionId,
  String rejectionReason = '',
}) async {
  if (!currentUserCanModerateSpot(spot)) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'regional-moderator-scope',
      message: 'This spot is outside your assigned countries.',
    );
  }
  final statusChanged = spot.status != status;
  final cleanRejectionReason = status == SpotStatus.rejected
      ? rejectionReason.trim()
      : '';
  final shouldNotifyNearbyMeetUsers =
      status == SpotStatus.approved &&
      spot.status != SpotStatus.approved &&
      spot.categories.contains('Meet');
  final shouldNotifyOtherAdmins =
      statusChanged &&
      (status == SpotStatus.approved || status == SpotStatus.rejected);

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final updatedSpot = spot.copyWith(
    status: status,
    rejectionReason: cleanRejectionReason,
    updatedAtMillis: nowMillis,
  );

  if (spot.id.isNotEmpty) {
    final decision = await sendModerationAction({
      'action': 'spot_review',
      'operation': 'decide',
      'spotId': spot.id,
      'sessionId': reviewSessionId,
      'status': spotStatusName(status),
      'rejectionReason': cleanRejectionReason,
    });
    if (decision['alreadyDecided'] == true) return;
  }

  // Keep the local UI responsive while Firestore sends the fresh snapshot.
  reviewSpots.value = reviewSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  submittedSpots.value = submittedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();
  savedSpots.value = savedSpots.value
      .map((item) => isSameSpot(item, spot) ? updatedSpot : item)
      .toList();

  upsertSpotIntoLocalImmediateCache(updatedSpot);

  if (spot.isTemporary && statusChanged) {
    await updateTemporarySpotForumTopicAfterSpotReview(
      updatedSpot,
      status,
      rejectionReason: cleanRejectionReason,
    );
  }

  if (shouldNotifyNearbyMeetUsers) {
    await createMeetSpotNotificationsForNearbyUsers(updatedSpot);
  }

  if (shouldNotifyOtherAdmins) {
    await createAdminSpotDecisionNotification(
      updatedSpot,
      status,
      rejectionReason: cleanRejectionReason,
    );
  }

  if (statusChanged &&
      (status == SpotStatus.approved || status == SpotStatus.rejected)) {
    await createSpotReviewUpdateNotification(
      updatedSpot,
      status,
      rejectionReason: cleanRejectionReason,
    );
  }

  if (statusChanged && status == SpotStatus.approved) {
    await createNewSpotNotificationForUsers(updatedSpot);
    await notifyAllUsersIfTemporarySpotIsToday(updatedSpot);

    await sendNewSpotPushToEligibleUsers(updatedSpot);
  }

  if (statusChanged &&
      status == SpotStatus.approved &&
      updatedSpot.id.isNotEmpty) {
    unawaited(
      syncXpWithServer({'action': 'sync_spot', 'spotId': updatedSpot.id}),
    );
  }

  if (statusChanged &&
      spot.id.isNotEmpty &&
      (status == SpotStatus.approved || status == SpotStatus.rejected)) {
    final ownerUid = spotNotificationOwnerUid(updatedSpot);
    await sendPushNotificationEvent({
      'type': 'spot_decision',
      'preferenceKey': 'reviewNotifications',
      if (ownerUid.isNotEmpty) 'recipientUserIds': [ownerUid],
      'spotId': spot.id,
      'status': spotStatusName(status),
      if (cleanRejectionReason.isNotEmpty)
        'rejectionReason': cleanRejectionReason,
    });
  }
}

Future<void> deleteSpotFromFirebase(CarSpot spot) async {
  if (spot.id.isNotEmpty) {
    await sendModerationAction({'action': 'delete_spot', 'spotId': spot.id});
    forumTopicsRefreshTick.value++;
  }

  removeSpotFromLocalImmediateCache(spot);

  reviewSpots.value = reviewSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  submittedSpots.value = submittedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  savedSpots.value = savedSpots.value
      .where((item) => !isSameSpot(item, spot))
      .toList();
  unawaited(saveSavedSpotIds());
}
