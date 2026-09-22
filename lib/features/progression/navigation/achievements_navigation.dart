import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/progression/data/xp_api.dart';

void openAchievements(BuildContext context) {
  Navigator.of(context).push(
    appPageRoute(
      builder: (_) => AchievementsScreen(
        language: appUiPreferences.language.name,
        load: () => xpScreenRequest('achievements'),
        selectForProfile: (id) async {
          await xpScreenRequest('select_achievement', {'achievementId': id});
        },
      ),
    ),
  );
}

void openPublicAchievements(BuildContext context, String userId) {
  if (userId == currentUser.uid) {
    openAchievements(context);
    return;
  }
  Navigator.of(context).push(
    appPageRoute(
      builder: (_) => AchievementsScreen(
        language: appUiPreferences.language.name,
        load: () => xpScreenRequest('public_achievements', {'userId': userId}),
      ),
    ),
  );
}
