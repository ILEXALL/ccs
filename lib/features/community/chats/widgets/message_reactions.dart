import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;

Widget messageReplyPreviewCard(
  MessageReplyPreviewData reply, {
  VoidCallback? onTap,
  bool compact = false,
}) {
  if (!reply.hasContent) {
    return const SizedBox.shrink();
  }

  final previewText = reply.text.trim().isNotEmpty
      ? reply.text.trim()
      : reply.photoUrl.trim().isNotEmpty
      ? trText('Photo')
      : trText('Message');

  final content = Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(10, compact ? 6 : 8, 10, compact ? 6 : 8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      border: Border(
        left: BorderSide(color: blue.withValues(alpha: 0.9), width: 3),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CcsText(
          reply.username.trim().isEmpty
              ? trText('Message')
              : displayUsername(reply.username),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: blue,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        CcsText(
          previewText,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  if (onTap == null) {
    return content;
  }
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: content,
  );
}

Map<String, int> messageReactionCounts(Map<String, String> reactions) {
  final counts = <String, int>{};
  for (final emoji in reactions.values) {
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  return counts;
}

Widget messageReactionBar({
  required Map<String, String> reactions,
  required String currentUid,
  required void Function(String emoji)? onEmojiTap,
}) {
  if (reactions.isEmpty) {
    return const SizedBox.shrink();
  }

  final counts = messageReactionCounts(reactions);
  final myEmoji = reactions[currentUid] ?? '';

  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final entry in counts.entries)
          InkWell(
            onTap: onEmojiTap == null ? null : () => onEmojiTap(entry.key),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: myEmoji == entry.key
                    ? blue.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: myEmoji == entry.key
                      ? blue.withValues(alpha: 0.72)
                      : Colors.white12,
                ),
              ),
              child: CcsText(
                '${entry.key} ${entry.value}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

Future<String?> showEmojiReactionPicker(
  BuildContext context, {
  String currentEmoji = '',
}) async {
  final controller = TextEditingController();
  const quick = <String>[
    '❤️',
    '👍',
    '👎',
    '😂',
    '🔥',
    '😍',
    '😮',
    '😢',
    '😡',
    '👏',
    '🎉',
    '💯',
  ];

  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: panelGlass,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CcsText(
                trText('React with emoji'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final emoji in quick)
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext, emoji),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 46,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: currentEmoji == emoji
                              ? blue.withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: currentEmoji == emoji
                                ? blue
                                : Colors.white12,
                          ),
                        ),
                        child: CcsText(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: false,
                maxLength: 32,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                decoration: InputDecoration(
                  hintText: trText('Or enter any emoji'),
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: blue),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (currentEmoji.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, ''),
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      label: CcsText(
                        trText('Remove reaction'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      final value = controller.text.trim();
                      if (value.isNotEmpty) {
                        Navigator.pop(sheetContext, value);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: blue),
                    child: CcsText(
                      trText('React'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  controller.dispose();
  return result;
}
