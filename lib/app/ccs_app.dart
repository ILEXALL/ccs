import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/controllers/reward_feedback.dart';
import 'package:ccs_app/app/app_shell.dart' show MainScreen;
import 'package:ccs_app/app/gates/access_gates.dart'
    show BannedUserGate, MaintenanceModeGate;
import 'package:ccs_app/app/gates/splash_screen.dart' show SplashScreen;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/theme/app_background.dart' show AppMapBackground;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show firebaseReady, rememberMeEnabled;

class CCSApp extends StatefulWidget {
  const CCSApp({super.key});
  @override
  State<CCSApp> createState() => _CCSAppState();
}

class _CCSAppState extends State<CCSApp> {
  late final Widget initialHome =
      firebaseReady &&
          rememberMeEnabled &&
          FirebaseAuth.instance.currentUser != null
      ? const MainScreen()
      : const SplashScreen();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        const lightTheme = false;
        final baseTheme = ThemeData.dark();

        return MaterialApp(
          navigatorKey: rewardNavigatorKey,
          scaffoldMessengerKey: rewardMessengerKey,
          debugShowCheckedModeBanner: false,
          title: 'CCS',
          locale: Locale(appUiPreferences.language.name),
          theme: baseTheme.copyWith(
            scaffoldBackgroundColor: Colors.transparent,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            textTheme: baseTheme.textTheme.apply(
              bodyColor: lightTheme ? const Color(0xFF181C22) : Colors.white,
              displayColor: lightTheme ? const Color(0xFF181C22) : Colors.white,
            ),
            iconTheme: IconThemeData(
              color: lightTheme ? const Color(0xFF242A33) : Colors.white70,
            ),
            inputDecorationTheme: InputDecorationTheme(
              labelStyle: TextStyle(
                color: lightTheme ? Colors.black54 : Colors.white60,
              ),
              hintStyle: TextStyle(
                color: lightTheme ? Colors.black38 : Colors.white24,
              ),
            ),
          ),
          builder: (context, child) {
            return MaintenanceModeGate(
              child: BannedUserGate(
                child: Stack(
                  fit: StackFit.expand,
                  children: [const AppMapBackground(), ?child],
                ),
              ),
            );
          },
          home: initialHome,
        );
      },
    );
  }
}
