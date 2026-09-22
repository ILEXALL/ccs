import 'package:ccs_app/app/gates/splash_screen.dart';
import 'package:ccs_app/core/theme/app_background.dart';
import 'package:ccs_app/features/progression/controllers/reward_feedback.dart';

void navigateAfterSignOut() {
  rewardNavigatorKey.currentState?.pushAndRemoveUntil(
    appPageRoute(builder: (_) => const SplashScreen()),
    (_) => false,
  );
}
