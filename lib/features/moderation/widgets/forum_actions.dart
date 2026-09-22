import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/moderation/data/forum_review.dart'
    show rejectForumTopic;
import 'package:ccs_app/features/moderation/data/forum_review_lease.dart'
    show ForumReviewLease;

Future<void> showRejectForumTopicDialog(
  BuildContext context,
  String topicId,
  ForumReviewLease lease,
) async {
  final controller = TextEditingController();
  try {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: CcsText(trText('Rejection reason')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 2000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: CcsText(trText('Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty)
                Navigator.pop(dialogContext, controller.text.trim());
            },
            child: CcsText(trText('Reject')),
          ),
        ],
      ),
    );
    if (reason != null) await rejectForumTopic(topicId, reason, lease);
  } finally {
    controller.dispose();
  }
}
