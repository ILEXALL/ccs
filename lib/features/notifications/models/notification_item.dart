import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationCenterItem {
  final String countryCode;
  final String id;
  final String title;
  final String body;
  final String type;
  final int createdAtMillis;
  final bool read;
  final DocumentReference<Map<String, dynamic>>? reference;
  final bool projectNews;
  final String spotId;
  final String spotName;
  final String chatId;
  final String topicId;
  final String reviewId;
  final String messageId;
  final String likeId;
  final String userId;
  final String addedByUid;
  final String actorUserId;
  final String actorUsername;
  final double friendLat;
  final double friendLng;
  final String status;
  final String rejectionReason;
  final int xpAmount;
  final String xpAction;
  final String xpTransactionId;

  const NotificationCenterItem({
    this.countryCode = '',
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAtMillis,
    required this.read,
    this.reference,
    this.projectNews = false,
    this.spotId = '',
    this.spotName = '',
    this.chatId = '',
    this.topicId = '',
    this.reviewId = '',
    this.messageId = '',
    this.likeId = '',
    this.userId = '',
    this.addedByUid = '',
    this.actorUserId = '',
    this.actorUsername = '',
    this.friendLat = 0,
    this.friendLng = 0,
    this.status = '',
    this.rejectionReason = '',
    this.xpAmount = 0,
    this.xpAction = '',
    this.xpTransactionId = '',
  });

  NotificationCenterItem copyWith({
    String? countryCode,
    String? id,
    String? title,
    String? body,
    String? type,
    int? createdAtMillis,
    bool? read,
    DocumentReference<Map<String, dynamic>>? reference,
    bool clearReference = false,
    bool? projectNews,
    String? spotId,
    String? spotName,
    String? chatId,
    String? topicId,
    String? reviewId,
    String? messageId,
    String? likeId,
    String? userId,
    String? addedByUid,
    String? actorUserId,
    String? actorUsername,
    double? friendLat,
    double? friendLng,
    String? status,
    String? rejectionReason,
    int? xpAmount,
    String? xpAction,
    String? xpTransactionId,
  }) {
    return NotificationCenterItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      read: read ?? this.read,
      reference: clearReference ? null : (reference ?? this.reference),
      projectNews: projectNews ?? this.projectNews,
      spotId: spotId ?? this.spotId,
      spotName: spotName ?? this.spotName,
      chatId: chatId ?? this.chatId,
      topicId: topicId ?? this.topicId,
      countryCode: countryCode ?? this.countryCode,
      reviewId: reviewId ?? this.reviewId,
      messageId: messageId ?? this.messageId,
      likeId: likeId ?? this.likeId,
      userId: userId ?? this.userId,
      addedByUid: addedByUid ?? this.addedByUid,
      actorUserId: actorUserId ?? this.actorUserId,
      actorUsername: actorUsername ?? this.actorUsername,
      friendLat: friendLat ?? this.friendLat,
      friendLng: friendLng ?? this.friendLng,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      xpAmount: xpAmount ?? this.xpAmount,
      xpAction: xpAction ?? this.xpAction,
      xpTransactionId: xpTransactionId ?? this.xpTransactionId,
    );
  }

  bool get canOpen =>
      !projectNews &&
      (spotId.trim().isNotEmpty ||
          chatId.trim().isNotEmpty ||
          topicId.trim().isNotEmpty ||
          type == 'global_chat_message' ||
          type == 'global_chat_admin' ||
          (type == 'chat_message' &&
              (actorUserId.trim().isNotEmpty ||
                  id.trim().startsWith('chat_'))) ||
          addedByUid.trim().isNotEmpty ||
          userId.trim().isNotEmpty ||
          ((type == 'new_spot' ||
                  type == 'temporary_event' ||
                  type == 'temporary_spot_today') &&
              spotName.trim().isNotEmpty) ||
          type == 'friend_request' ||
          type == 'spot_pending_review' ||
          type == 'user_report_new' ||
          type == 'xp_reward' ||
          type == 'friend_nearby' ||
          type == 'friend_at_spot' ||
          type == 'friend_live_sharing');
}
