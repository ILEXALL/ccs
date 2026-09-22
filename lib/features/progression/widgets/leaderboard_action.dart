import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/progression/screens/leaderboard_screen.dart'
    show XpLeaderboardScreen;

class CcsXpLeaderboardAction extends StatelessWidget {
  const CcsXpLeaderboardAction({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: trText('XP Leaderboard'),
      child: Semantics(
        label: trText('XP Leaderboard'),
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                appPageRoute(builder: (_) => const XpLeaderboardScreen()),
              );
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: blue.withValues(alpha: 0.42)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.emoji_events_outlined, color: blue, size: 23),
                  SizedBox(width: 5),
                  CcsText(
                    'Top 100',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: blue,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
