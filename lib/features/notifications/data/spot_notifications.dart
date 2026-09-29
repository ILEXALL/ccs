import 'package:ccs_app/features/spots/models/spot_owner.dart'
    show spotNotificationOwnerUid;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show createUserNotification;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;

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

// The server resolves recipients, applies preferences and creates bell entries.
// Do not scan users or write a second copy of notification history on the device.
Future<void> sendNewSpotPushToEligibleUsers(CarSpot spot) async {
  if (spot.id.trim().isEmpty || spot.status != SpotStatus.approved) return;
  await sendPushNotificationEvent({
    'type': spot.isTemporary || spot.isGroupSpot
        ? 'temporary_event'
        : 'new_spot',
    'spotId': spot.id,
  });
}
