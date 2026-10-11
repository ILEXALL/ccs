import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show GlobalSmallAvatar;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

class SpotGroupLabels extends StatelessWidget {
  final CarSpot spot;
  final bool useChips;
  const SpotGroupLabels({super.key, required this.spot, this.useChips = false});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      if (!useChips)
        CcsText(
          trText('Group'),
          style: const TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      for (final group in spot.sharedGroups)
        Container(
          padding: useChips
              ? const EdgeInsets.symmetric(horizontal: 7, vertical: 5)
              : EdgeInsets.zero,
          decoration: useChips
              ? BoxDecoration(
                  color: const Color(0xFF8BD9E5).withValues(alpha: .07),
                  border: Border.all(
                    color: const Color(0xFF8BD9E5).withValues(alpha: .18),
                  ),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlobalSmallAvatar(
                avatarUrl: stringFromFirebase(group['avatarUrl'], ''),
                username: stringFromFirebase(group['name'], 'Group'),
                size: 18,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: CcsText(
                  stringFromFirebase(group['name'], 'Group'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: useChips
                        ? const Color(0xFFB2E2EA)
                        : Colors.cyanAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
