import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/community/forum/data/forum_reply_counts.dart'
    show fetchAccurateForumReplyCount, forumReplyCountCache;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show inAppBadges;
import 'package:ccs_app/features/notifications/models/badge_label.dart'
    show compactBadgeLabel;

Widget forumReplyCountBadge({
  required String topicId,
  required int fallbackCount,
}) {
  return FutureBuilder<int>(
    future: fetchAccurateForumReplyCount(topicId, fallbackCount),
    initialData: forumReplyCountCache[topicId.trim()],
    builder: (context, snapshot) {
      final count = math.max(0, snapshot.data ?? fallbackCount);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(height: 4),
          CcsText(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
    },
  );
}

class ForumUnreadBadge extends StatelessWidget {
  final String? topicId;
  final String? categoryId;
  final String countryCode;
  const ForumUnreadBadge({
    super.key,
    this.topicId,
    this.categoryId,
    this.countryCode = 'LV',
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: inAppBadges,
    builder: (context, _) {
      final count = topicId != null
          ? inAppBadges.forumTopicCount(topicId!, countryCode)
          : inAppBadges.forumCategoryCount(categoryId!);
      if (count == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Badge(
          backgroundColor: Colors.redAccent,
          label: CcsText(compactBadgeLabel(count)),
        ),
      );
    },
  );
}
