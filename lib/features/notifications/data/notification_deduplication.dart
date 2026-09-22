import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show
        notificationCenterDisplayBody,
        notificationCenterItemIsRejected,
        spotNameFromNotificationBody;
import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show chatIdFromNotificationItem;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;

String notificationCenterSpotDedupKey(NotificationCenterItem item) {
  final cleanName = item.spotName.trim().toLowerCase();
  if (cleanName.isNotEmpty) {
    return 'name:$cleanName';
  }

  final bodyName = spotNameFromNotificationBody(
    item.type,
    item.body,
  ).trim().toLowerCase();
  if (bodyName.isNotEmpty) {
    return 'name:$bodyName';
  }

  final cleanSpotId = item.spotId.trim();
  if (cleanSpotId.isNotEmpty) {
    return 'id:$cleanSpotId';
  }

  return '';
}

int rejectedNotificationStrength(NotificationCenterItem item) {
  final body = item.body.toLowerCase();
  var score = 1;

  if (body.contains('rejected')) {
    score = 2;
  }
  if (body.contains('reason:')) {
    score = 3;
  }
  if (item.rejectionReason.trim().isNotEmpty) {
    score = 4;
  }

  // Generic legacy wording is weaker than the explicit rejected notification,
  // even if we later enrich it with the rejection reason from the spot doc.
  if (body.contains('not approved')) {
    score -= 1;
  }

  return score;
}

List<NotificationCenterItem> removeDuplicateSpotReviewNotifications(
  List<NotificationCenterItem> items,
) {
  final strongestRejectedBySpot = <String, NotificationCenterItem>{};

  for (final item in items) {
    if (!notificationCenterItemIsRejected(item)) {
      continue;
    }

    final spotKey = notificationCenterSpotDedupKey(item);
    if (spotKey.isEmpty) {
      continue;
    }

    final existing = strongestRejectedBySpot[spotKey];
    if (existing == null ||
        rejectedNotificationStrength(item) >=
            rejectedNotificationStrength(existing)) {
      strongestRejectedBySpot[spotKey] = item;
    }
  }

  if (strongestRejectedBySpot.isEmpty) {
    return items;
  }

  return items.where((item) {
    if (!notificationCenterItemIsRejected(item)) {
      return true;
    }

    final spotKey = notificationCenterSpotDedupKey(item);
    if (spotKey.isEmpty) {
      return true;
    }

    final strongest = strongestRejectedBySpot[spotKey];
    if (strongest == null || identical(strongest, item)) {
      return true;
    }

    // Keep only the best rejected notification per spot. This removes the
    // older generic "was not approved" item when the proper rejected item
    // with a reason exists.
    return false;
  }).toList();
}

bool notificationCenterItemIsPublicSpot(NotificationCenterItem item) {
  return item.type == 'new_spot' || item.type == 'temporary_event';
}

String publicSpotNotificationDedupKey(NotificationCenterItem item) {
  final cleanName = item.spotName.trim().toLowerCase();
  if (cleanName.isNotEmpty) {
    return '${item.type}:name:$cleanName';
  }

  final bodyName = spotNameFromNotificationBody(
    item.type,
    item.body,
  ).trim().toLowerCase();
  if (bodyName.isNotEmpty) {
    return '${item.type}:name:$bodyName';
  }

  final cleanSpotId = item.spotId.trim();
  if (cleanSpotId.isNotEmpty) {
    return '${item.type}:id:$cleanSpotId';
  }

  return '';
}

int publicSpotNotificationStrength(NotificationCenterItem item) {
  var score = 0;
  if (item.spotId.trim().isNotEmpty) {
    score += 4;
  }
  if (item.spotName.trim().isNotEmpty) {
    score += 2;
  }

  // Backend-created public spot notifications are sent after the local write
  // and use the shorter body that opens correctly. Prefer them over the older
  // client-created duplicate that says "was added in ...".
  if (!item.body.toLowerCase().contains('was added in')) {
    score += 1;
  }

  if (item.reference == null) {
    score += 1;
  }

  return score;
}

List<NotificationCenterItem> removeDuplicatePublicSpotNotifications(
  List<NotificationCenterItem> items,
) {
  final strongestBySpot = <String, NotificationCenterItem>{};

  for (final item in items) {
    if (!notificationCenterItemIsPublicSpot(item)) {
      continue;
    }

    final spotKey = publicSpotNotificationDedupKey(item);
    if (spotKey.isEmpty) {
      continue;
    }

    final existing = strongestBySpot[spotKey];
    if (existing == null ||
        publicSpotNotificationStrength(item) >
            publicSpotNotificationStrength(existing) ||
        (publicSpotNotificationStrength(item) ==
                publicSpotNotificationStrength(existing) &&
            item.createdAtMillis >= existing.createdAtMillis)) {
      strongestBySpot[spotKey] = item;
    }
  }

  if (strongestBySpot.isEmpty) {
    return items;
  }

  return items.where((item) {
    if (!notificationCenterItemIsPublicSpot(item)) {
      return true;
    }

    final spotKey = publicSpotNotificationDedupKey(item);
    if (spotKey.isEmpty) {
      return true;
    }

    final strongest = strongestBySpot[spotKey];
    return strongest == null || identical(strongest, item);
  }).toList();
}

String notificationCenterActionDedupKey(NotificationCenterItem item) {
  final type = item.type.trim();
  final actorKey = item.actorUserId.trim().isNotEmpty
      ? 'uid:${item.actorUserId.trim()}'
      : 'user:${item.actorUsername.trim().toLowerCase()}';

  if (type == 'global_chat_message' || type == 'global_chat_admin') {
    final messageKey = item.messageId.trim();
    if (messageKey.isNotEmpty) {
      // Staff can receive both the normal Global Chat item and an admin
      // moderation item for the same message. Backend history can add another
      // copy. Treat all of them as one action in the bell.
      return 'global_chat:$messageKey';
    }

    final bodyKey = notificationCenterDisplayBody(item).trim().toLowerCase();
    if (bodyKey.isNotEmpty) {
      final bucket = (item.createdAtMillis / 60000).floor();
      return 'global_chat:$actorKey:$bodyKey:$bucket';
    }
  }

  if (type == 'forum_reply' || type == 'forum_reply_admin') {
    final topicKey = item.topicId.trim();
    final messageKey = item.messageId.trim();
    if (topicKey.isNotEmpty && messageKey.isNotEmpty) {
      // Older senders created both a normal reply row and a staff-only row.
      // They represent the same forum message in the bell and app badge.
      return 'forum_reply:$topicKey:$messageKey';
    }

    final bodyKey = notificationCenterDisplayBody(item).trim().toLowerCase();
    if (topicKey.isNotEmpty && bodyKey.isNotEmpty) {
      final bucket = (item.createdAtMillis / 60000).floor();
      return 'forum_reply:$topicKey:$actorKey:$bodyKey:$bucket';
    }
  }

  if (type == 'chat_message') {
    final chatKey = chatIdFromNotificationItem(item).trim();
    final messageKey = item.messageId.trim().isNotEmpty
        ? item.messageId.trim()
        : (() {
            final match = RegExp(
              r'^chat_[^_]+_(.+?)(?:_[^_]+)?$',
            ).firstMatch(item.id.trim());
            return match?.group(1)?.trim() ?? '';
          })();
    if (chatKey.isNotEmpty && messageKey.isNotEmpty) {
      return 'chat_message:$chatKey:$messageKey';
    }

    final bodyKey = notificationCenterDisplayBody(item).trim().toLowerCase();
    if (chatKey.isNotEmpty && bodyKey.isNotEmpty) {
      final bucket = (item.createdAtMillis / 60000).floor();
      return 'chat_message:$chatKey:$actorKey:$bodyKey:$bucket';
    }
  }

  if (type == 'spot_comment') {
    if (item.reviewId.trim().isNotEmpty) {
      return 'spot_comment:review:${item.reviewId.trim()}';
    }

    final spotKey = notificationCenterSpotDedupKey(item);
    if (spotKey.isNotEmpty) {
      final bucket = (item.createdAtMillis / 60000).floor();
      return 'spot_comment:$spotKey:$actorKey:$bucket';
    }
  }

  if (type == 'spot_like') {
    if (item.likeId.trim().isNotEmpty) {
      return 'spot_like:like:${item.likeId.trim()}';
    }

    final match = RegExp(r'^spot_like_(.+)$').firstMatch(item.id.trim());
    final idLikeKey = match?.group(1)?.trim() ?? '';
    if (idLikeKey.isNotEmpty) {
      return 'spot_like:like:$idLikeKey';
    }

    final spotKey = notificationCenterSpotDedupKey(item);
    if (spotKey.isNotEmpty) {
      return 'spot_like:$spotKey:$actorKey';
    }
  }

  return '';
}

int notificationCenterActionStrength(NotificationCenterItem item) {
  var score = 0;
  if (item.reference != null) score += 8;
  if (item.spotId.trim().isNotEmpty) score += 4;
  if (item.spotName.trim().isNotEmpty) score += 3;
  if (item.chatId.trim().isNotEmpty) score += 4;
  if (item.reviewId.trim().isNotEmpty) score += 5;
  if (item.messageId.trim().isNotEmpty) score += 5;
  if (item.likeId.trim().isNotEmpty) score += 5;
  if (item.actorUserId.trim().isNotEmpty) score += 2;
  if (item.actorUsername.trim().isNotEmpty) score += 1;

  final body = item.body.trim().toLowerCase();
  if (item.type == 'spot_comment') {
    // Prefer the row that still contains the actual comment text, as long as it
    // also has enough metadata to open the target spot.
    if (body.startsWith('@') && !body.contains('commented on')) score += 2;
  }
  if (item.type == 'chat_message') {
    if (body.startsWith('@')) score += 1;
  }

  return score;
}

List<NotificationCenterItem> removeDuplicateActionNotifications(
  List<NotificationCenterItem> items,
) {
  final strongestByKey = <String, NotificationCenterItem>{};

  for (final item in items) {
    final key = notificationCenterActionDedupKey(item);
    if (key.isEmpty) {
      continue;
    }

    final existing = strongestByKey[key];
    if (existing == null ||
        notificationCenterActionStrength(item) >
            notificationCenterActionStrength(existing) ||
        (notificationCenterActionStrength(item) ==
                notificationCenterActionStrength(existing) &&
            item.createdAtMillis >= existing.createdAtMillis)) {
      strongestByKey[key] = item;
    }
  }

  if (strongestByKey.isEmpty) {
    return items;
  }

  return items.where((item) {
    final key = notificationCenterActionDedupKey(item);
    if (key.isEmpty) {
      return true;
    }

    final strongest = strongestByKey[key];
    return strongest == null || identical(strongest, item);
  }).toList();
}
