import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDate, twoDigits;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show UserAvatarFallback;

class ChatTitleAvatar extends StatelessWidget {
  final String photoUrl;
  final String title;

  const ChatTitleAvatar({
    super.key,
    required this.photoUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final firstLetter = title.trim().isEmpty
        ? '?'
        : title.trim().substring(0, 1).toUpperCase();

    if (isNetworkUrl(photoUrl)) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              UserAvatarFallback(size: 34, icon: Icons.person),
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Center(
        child: CcsText(
          firstLetter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

String formatChatMessageTime(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }
  final value = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String chatDateDividerLabel(int createdAtMillis) {
  if (createdAtMillis <= 0) {
    return '';
  }
  final value = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(value.year, value.month, value.day);
  final diffDays = today.difference(messageDay).inDays;

  if (diffDays == 0) {
    return trText('Today');
  }
  if (diffDays == 1) {
    return trText('Yesterday');
  }
  return formatShortDate(value);
}

Widget chatDateDivider(String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        const Expanded(child: Divider(color: Colors.white12)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: CcsText(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white12)),
      ],
    ),
  );
}
