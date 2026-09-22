import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/chat_identity.dart'
    show directChatIdFor;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/notifications/models/notification_types.dart'
    show selfAuthoredMessageNotificationTypes;
import 'package:ccs_app/features/progression/models/xp_progression.dart'
    show formatXpValue;
import 'package:ccs_app/features/progression/widgets/xp_labels.dart'
    show xpTransactionActionLabel;

bool notificationCenterItemIsSelfAuthoredMessage(
  NotificationCenterItem item,
  String currentUid,
) {
  final cleanCurrentUid = currentUid.trim();
  final type = item.type.trim();
  if (cleanCurrentUid.isEmpty ||
      !selfAuthoredMessageNotificationTypes.contains(type)) {
    return false;
  }

  final actorUserId = item.actorUserId.trim();
  return actorUserId.isNotEmpty && actorUserId == cleanCurrentUid;
}

bool notificationCenterItemIsRejected(NotificationCenterItem item) {
  final status = item.status.trim().toLowerCase();
  final title = item.title.trim().toLowerCase();
  final body = item.body.trim().toLowerCase();
  final type = item.type.trim().toLowerCase();

  return status == 'rejected' ||
      status.contains('reject') ||
      type == 'spot_rejected_by_admin' ||
      type.contains('reject') ||
      title.contains('rejected') ||
      title.contains('not approved') ||
      body.contains('rejected') ||
      body.contains('was rejected') ||
      body.contains('not approved') ||
      item.rejectionReason.trim().isNotEmpty;
}

String bodyWithRejectionReason(String body, String reason) {
  final cleanReason = reason.trim();
  if (cleanReason.isEmpty || body.toLowerCase().contains('reason:')) {
    return body;
  }

  final cleanBody = body.trim();
  if (cleanBody.isEmpty) {
    return 'Your spot was rejected. Reason: $cleanReason';
  }

  return '$cleanBody Reason: $cleanReason';
}

IconData notificationCenterIcon(NotificationCenterItem item) {
  if (item.projectNews) {
    return Icons.campaign;
  }

  // Rejection must always win over any generic review/update type. Some
  // notification payloads arrive as spot_review_update, so deciding only from
  // the type can incorrectly show the green approval check.
  if (notificationCenterItemIsRejected(item)) {
    return Icons.cancel;
  }

  return switch (item.type) {
    'spot_like' => Icons.favorite,
    'spot_comment' => Icons.chat_bubble,
    'chat_message' => Icons.mark_chat_unread,
    'spot_review_update' =>
      notificationCenterItemIsRejected(item)
          ? Icons.cancel
          : Icons.check_circle,
    'spot_pending_review' => Icons.fact_check,
    'global_chat_message' || 'global_chat_admin' => Icons.public,
    'xp_reward' => Icons.emoji_events_outlined,
    'forum_topic_created' ||
    'forum_reply' ||
    'forum_topic_pending' ||
    'forum_reply_admin' => Icons.forum_outlined,
    'moderator_user_banned' => Icons.gavel,
    'user_report_new' => Icons.report_outlined,
    'spot_approved_by_admin' => Icons.check_circle,
    'spot_rejected_by_admin' => Icons.cancel,
    'new_spot' => Icons.add_location_alt,
    'temporary_event' || 'temporary_spot_today' => Icons.event_available,
    'friend_request' => Icons.person_add_alt_1,
    'friend_nearby' ||
    'friend_at_spot' ||
    'friend_live_sharing' => Icons.location_on,
    _ => Icons.notifications,
  };
}

Color notificationCenterColor(NotificationCenterItem item) {
  if (item.projectNews) {
    return const Color(0xFFFFB300);
  }

  // Same rule as the icon: any rejected review notification is red.
  if (notificationCenterItemIsRejected(item)) {
    return Colors.redAccent;
  }

  return switch (item.type) {
    'spot_like' => Colors.redAccent,
    'spot_comment' || 'chat_message' => blue,
    'xp_reward' => const Color(0xFFFFB300),
    'spot_review_update' =>
      notificationCenterItemIsRejected(item) ? Colors.redAccent : Colors.green,
    'spot_rejected_by_admin' => Colors.redAccent,
    'spot_approved_by_admin' => Colors.green,
    'spot_pending_review' => blue,
    'global_chat_message' ||
    'global_chat_admin' ||
    'forum_topic_created' ||
    'forum_reply' ||
    'forum_topic_pending' ||
    'forum_reply_admin' => blue,
    'user_report_new' => Colors.orangeAccent,
    'new_spot' => const Color(0xFF9B35FF),
    'temporary_event' || 'temporary_spot_today' => const Color(0xFFFF7A00),
    'friend_request' => blue,
    'friend_nearby' ||
    'friend_at_spot' ||
    'friend_live_sharing' => Colors.greenAccent.shade700,
    _ => blue,
  };
}

String notificationCenterTime(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }

  final time = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inMinutes < 1) {
    return trText('Just now');
  }

  if (difference.inHours < 1) {
    return '${difference.inMinutes} min';
  }

  if (difference.inDays < 1) {
    return '${difference.inHours} h';
  }

  final day = time.day.toString().padLeft(2, '0');
  final month = time.month.toString().padLeft(2, '0');
  return '$day.$month.${time.year}';
}

String actorUsernameFromNotificationBody(String body) {
  final match = RegExp(r'^@([^:\s]+):').firstMatch(body.trim());
  return match?.group(1)?.trim() ?? '';
}

String chatNotificationTitle(String actorUsername) {
  final cleanUsername = actorUsername.trim().replaceAll('@', '');
  return cleanUsername.isEmpty ? 'Messages' : 'Message from @$cleanUsername';
}

String notificationCenterDisplayTitle(NotificationCenterItem item) {
  if (item.type == 'chat_message') {
    return chatNotificationTitle(item.actorUsername);
  }

  if (item.type == 'xp_reward') {
    return 'XP reward';
  }

  return item.title;
}

String notificationCenterDisplayBody(NotificationCenterItem item) {
  final body = item.body.trim();
  if (item.type == 'xp_reward') {
    if (body.contains(' — ')) return body;
    final amount = item.xpAmount > 0 ? item.xpAmount : 0;
    final amountLabel = amount > 0 ? '+${formatXpValue(amount)} XP' : 'XP';
    final actionLabel = trText(xpTransactionActionLabel(item.xpAction)).trim();
    return actionLabel.isEmpty || actionLabel == 'XP'
        ? amountLabel
        : '$amountLabel - $actionLabel';
  }

  if (item.type != 'chat_message') {
    if (notificationCenterItemIsRejected(item) &&
        item.rejectionReason.trim().isNotEmpty &&
        !body.toLowerCase().contains('reason:')) {
      final spotName = item.spotName.trim().isEmpty
          ? 'Your spot'
          : item.spotName.trim();
      return '$spotName was rejected. Reason: ${item.rejectionReason.trim()}';
    }
    return body;
  }

  final messageMatch = RegExp(r'^@[^:]+:\s*(.+)$').firstMatch(body);
  return messageMatch?.group(1)?.trim() ?? body;
}

String spotNameFromNotificationBody(String type, String body) {
  final cleanType = type.trim();
  final cleanBody = body.trim();
  if (cleanBody.isEmpty) {
    return '';
  }

  if (cleanType == 'spot_like') {
    final match = RegExp(
      r'\bliked\s+(.+?)\.?$',
      caseSensitive: false,
    ).firstMatch(cleanBody);
    return match?.group(1)?.trim().replaceAll(RegExp(r'\.+$'), '') ?? '';
  }

  if (cleanType == 'spot_comment') {
    final match = RegExp(
      r'\bcommented\s+on\s+(.+?)(?::|\.)?$',
      caseSensitive: false,
    ).firstMatch(cleanBody);
    return match?.group(1)?.trim().replaceAll(RegExp(r'\.+$'), '') ?? '';
  }

  if (cleanType == 'new_spot' ||
      cleanType == 'temporary_event' ||
      cleanType == 'temporary_spot_today') {
    final patterns = [
      RegExp(
        r'^(.+?)\s+(?:event\s+)?was\s+added(?:\s+in\s+.+)?\.?$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(.+?)\s+(?:event\s+)?(?:was\s+)?added(?:\s+in\s+.+)?\.?$',
        caseSensitive: false,
      ),
      // Backend/user notification rows can be shorter, for example:
      // "Oak Burgers in Riga, Latvia". Extract the name before " in ".
      RegExp(r'^(.+?)\s+in\s+.+$', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanBody);
      final value = match?.group(1)?.trim().replaceAll(RegExp(r'\.+$'), '');
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  if (cleanType == 'spot_review_update' ||
      cleanType == 'spot_rejected_by_admin' ||
      cleanType == 'spot_approved_by_admin' ||
      cleanType == 'spot_pending_review') {
    final patterns = [
      RegExp(r'^(.+?)\s+was\s+not\s+approved\.?$', caseSensitive: false),
      RegExp(
        r'^(.+?)\s+was\s+rejected(?:\.|\s+Reason:|$)',
        caseSensitive: false,
      ),
      RegExp(r'^(.+?)\s+was\s+approved\.?$', caseSensitive: false),
      RegExp(r'^(.+?)\s+is\s+waiting\s+for\s+review\.?$', caseSensitive: false),
      RegExp(r'^(.+?)\s+rejected\b', caseSensitive: false),
      RegExp(r'^(.+?)\s+approved\b', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanBody);
      final value = match?.group(1)?.trim().replaceAll(RegExp(r'\.+$'), '');
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
  }

  return '';
}

String chatIdFromNotificationItem(NotificationCenterItem item) {
  final cleanChatId = item.chatId.trim();
  if (cleanChatId.isNotEmpty) {
    return cleanChatId;
  }

  final firebaseUser = FirebaseAuth.instance.currentUser;
  final currentUid = firebaseUser?.uid ?? '';
  final itemId = item.id.trim();
  if (currentUid.isNotEmpty && itemId.startsWith('chat_')) {
    final match = RegExp(
      '^chat_(.+)_\\d+_${RegExp.escape(currentUid)}\$',
    ).firstMatch(itemId);
    final parsedChatId = match?.group(1)?.trim() ?? '';
    if (parsedChatId.isNotEmpty) {
      return parsedChatId;
    }
  }

  final actorUid = item.actorUserId.trim();
  if (currentUid.isNotEmpty && actorUid.isNotEmpty && actorUid != currentUid) {
    return directChatIdFor(currentUid, actorUid);
  }

  return '';
}
