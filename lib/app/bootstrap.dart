import 'package:ccs_app/core/time/trusted_clock.dart';
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'app_navigation.dart';
import 'app_services.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ccs_app/firebase_options.dart';
import 'package:ccs_app/features/notifications/models/notification_freshness.dart';
import 'package:ccs_app/app/ccs_app.dart' show CCSApp;
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show currentAppVersion, initializeMaintenanceMode;
import 'package:ccs_app/core/config/app_config.dart' show googleServerClientId;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show firestoreDebugTracker;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/theme/app_theme.dart' show warmUpAppMapBackground;
import 'package:ccs_app/features/auth/data/auth_preferences.dart'
    show loadRememberMePreference;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show firebaseReady, googleSignInSetupError, rememberMeEnabled;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show startCurrentUserDocumentWatcher;
import 'package:ccs_app/features/auth/data/sign_in.dart'
    show loadCurrentFirebaseUser;
import 'package:ccs_app/features/notifications/data/badge_sync.dart'
    show startAppIconBadgeSync;
import 'package:ccs_app/features/notifications/data/push_notifications.dart'
    show initializePushNotificationsForCurrentUser;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show startNotificationCenterUnreadWatcher;
import 'package:ccs_app/features/spots/data/saved_spots.dart'
    show loadSavedSpotsFromPrefs;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show initializeSpotCountryFiltersForUser, loadSpotCategoryFiltersPreference;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show startCurrentUserLikedSpotsSync;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show startFirebaseSpotSync;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> bootstrap() async {
  configureAppNavigation();
  configureAppServices();
  notificationLaunchTime = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  trustedClock.addListener(() => reviewSpots.value = [...reviewSpots.value]);
  trustedClock.start();
  startAppIconBadgeSync();
  final backgroundReady = warmUpAppMapBackground();
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    currentAppVersion = packageInfo.version;
  } catch (error) {
    currentAppVersion = '';
    debugPrint('App version lookup failed: $error');
  }
  await Future.wait([
    appUiPreferences.load(),
    firestoreDebugTracker.loadPersisted(),
  ]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    // Register before Firebase requests. Debug tokens must be registered in
    // Firebase Console; production builds always use device attestation.
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
    await initializeMaintenanceMode();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Google Sign-In needs one setup call before we use the login button.
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: googleServerClientId,
      );
    } catch (error) {
      googleSignInSetupError = error.toString();
    }

    rememberMeEnabled = await loadRememberMePreference();
    await Future.wait([
      loadSpotCategoryFiltersPreference(),
      loadSavedSpotsFromPrefs(),
    ]);

    final appUser = await loadCurrentFirebaseUser();
    if (appUser != null) {
      await initializeSpotCountryFiltersForUser(appUser);
      startCurrentUserDocumentWatcher();
      if (!appUser.banActive) {
        startFirebaseSpotSync();
        unawaited(startCurrentUserLikedSpotsSync());
        unawaited(initializePushNotificationsForCurrentUser());
        startNotificationCenterUnreadWatcher();
      }
    }
  } catch (error) {
    // Do not let a Firebase/Google services problem crash the app on startup.
    firebaseReady = false;
    googleSignInSetupError = error.toString();
    rememberMeEnabled = false;
  }

  await backgroundReady;
  runApp(const CCSApp());
}
