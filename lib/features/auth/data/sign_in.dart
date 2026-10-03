import 'dart:async';
import 'dart:io';
import 'package:ccs_app/features/auth/data/apple_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/core/config/app_config.dart' show telegramAuthBaseUrls;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        mapFromFirebase,
        nullableTimestampMillisFromFirebase,
        stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/network/json_http.dart' show getJsonFromUrl;
import 'package:ccs_app/core/platform/device_identity.dart'
    show getAppDeviceIds;
import 'package:ccs_app/features/auth/data/account_bans.dart'
    show userBanIsActive, userBanReasonFromFirebase;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, firebaseReady, googleSignInSetupError, setCurrentUser;
import 'package:ccs_app/features/auth/data/device_bans.dart'
    show ensureAppDeviceIsAllowed;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show startCurrentUserDocumentWatcher;
import 'package:ccs_app/features/auth/data/usernames.dart'
    show
        boundedProfileUsername,
        cleanProfileUsername,
        makeUsernameFromFirebaseUser,
        providerNameForFirebaseUser,
        reserveUsernameForCurrentUser,
        usernameKey;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show
        moderatorCountryCodesFromFirebase,
        userDataHasCommunityModerationAccess;
import 'package:ccs_app/features/notifications/data/push_notifications.dart'
    show initializePushNotificationsForCurrentUser;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show startNotificationCenterUnreadWatcher;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show garageCars, userSettings;
import 'package:ccs_app/features/profile/models/garage_car.dart'
    show garageCarsFromFirebase;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show initializeSpotCountryFiltersForUser;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show startCurrentUserLikedSpotsSync;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show startFirebaseSpotSync;
import 'package:ccs_app/shared/models/countries.dart'
    show canonicalSpotCountryName, countryIsoCode;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, roleName;

Future<UserRole> defaultRoleForNewFirebaseUser() async {
  // New users must always be regular users.
  // Admin rights are assigned manually in Firebase Console.
  return UserRole.user;
}

typedef NewUserNicknameRequester =
    Future<String?> Function(User firebaseUser, String fallbackUsername);

Future<void> cancelNewProfileSignIn() async {
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {}

  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
}

Future<String?> usernameOverrideForNewFirebaseUser({
  required User firebaseUser,
  required String fallbackUsername,
  NewUserNicknameRequester? requestNewUserNickname,
}) async {
  final snapshot = await usersCollection()
      .doc(firebaseUser.uid)
      .debugGet(null, 'login: check existing user profile');

  if (snapshot.exists) {
    return null;
  }

  if (requestNewUserNickname == null) {
    return boundedProfileUsername(fallbackUsername);
  }

  final selectedNickname = await requestNewUserNickname(
    firebaseUser,
    boundedProfileUsername(fallbackUsername),
  );
  final cleanNickname = cleanProfileUsername(selectedNickname ?? '');

  if (cleanNickname.isEmpty) {
    await cancelNewProfileSignIn();
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'nickname-required',
      message: 'Nickname is required to create your account.',
    );
  }

  return cleanNickname;
}

Future<AppUser?> loadCurrentFirebaseUser() async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return null;
  }

  try {
    setCurrentUser(
      await saveFirebaseUser(
        firebaseUser,
        provider: providerNameForFirebaseUser(firebaseUser),
      ),
    );
    return currentUser;
  } catch (_) {
    return null;
  }
}

// Only new accounts request location. A failed lookup leaves the profile
// unknown so the user can choose it; language and the map's default are not
// evidence of a user's country.
Future<({String city, String country})> detectNewAccountLocation() async {
  const unknown = (city: '', country: '');
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return unknown;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return unknown;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final places = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 8));
    if (places.isEmpty) return unknown;
    return profileLocationFromPlacemark(places.first);
  } catch (error) {
    debugPrint('Initial profile location unavailable: $error');
    return unknown;
  }
}

({String city, String country}) profileLocationFromPlacemark(Placemark place) {
  final city =
      [place.locality, place.subAdministrativeArea, place.administrativeArea]
          .whereType<String>()
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  final code =
      countryIsoCode(place.isoCountryCode ?? '') ??
      countryIsoCode(place.country ?? '');
  return (
    city: city,
    country: code == null
        ? (place.country ?? '').trim()
        : canonicalSpotCountryName(code),
  );
}

Future<AppUser> saveFirebaseUser(
  User firebaseUser, {
  required String provider,
  String? displayNameOverride,
  String? usernameOverride,
  String? emailOverride,
  String? photoUrlOverride,
  String? telegramUsername,
}) async {
  final userRef = FirebaseFirestore.instance
      .collection('users')
      .doc(firebaseUser.uid);
  final snapshot = await userRef.debugGet();
  final data = snapshot.data();
  final isNewUser = !snapshot.exists;

  if (!isNewUser && data?['deleted'] == true) {
    throw FirebaseException(
      plugin: 'firebase_auth',
      code: 'user-deleted',
      message: 'This account was removed.',
    );
  }

  final appDeviceIds = await getAppDeviceIds();
  final appDeviceId = appDeviceIds.first;
  await ensureAppDeviceIsAllowed(deviceIds: appDeviceIds);

  final role = isNewUser
      ? await defaultRoleForNewFirebaseUser()
      : roleFromFirebase(data?['role']);
  final existingBannedUntilMillis = nullableTimestampMillisFromFirebase(
    data?['bannedUntil'],
  );
  final existingBanReason = userBanReasonFromFirebase(data);
  final name = (data?['name'] as String?)?.trim().isNotEmpty == true
      ? data!['name'] as String
      : displayNameOverride?.trim().isNotEmpty == true
      ? displayNameOverride!.trim()
      : firebaseUser.displayName ?? 'CCS Driver';
  final rawUsername = (data?['username'] as String?)?.trim().isNotEmpty == true
      ? data!['username'] as String
      : usernameOverride?.trim().isNotEmpty == true
      ? usernameOverride!.trim()
      : makeUsernameFromFirebaseUser(firebaseUser);
  final initialLocation = isNewUser
      ? await detectNewAccountLocation()
      : (city: '', country: '');
  final city = stringFromFirebase(data?['city'], initialLocation.city).trim();
  final country = stringFromFirebase(
    data?['country'],
    initialLocation.country,
  ).trim();
  final photoUrl = (data?['photoUrl'] as String?)?.trim().isNotEmpty == true
      ? data!['photoUrl'] as String
      : photoUrlOverride ?? firebaseUser.photoURL;
  final bio = (data?['bio'] as String?)?.trim().isNotEmpty == true
      ? data!['bio'] as String
      : 'Night drive setup, Riga spots, clean reels, and low car routes.';
  final avatarPath = (data?['avatarPath'] as String?)?.trim().isNotEmpty == true
      ? data!['avatarPath'] as String
      : null;
  final verified = data?['verified'] == true;
  final globalChatModerator = userDataHasCommunityModerationAccess(data);
  final moderatorCountryCodes = moderatorCountryCodesFromFirebase(
    data?['moderatorCountryCodes'],
  );
  final settings = UserSettingsData.fromFirebase(data?['settings']);
  final garage = garageCarsFromFirebase(data?['garage']);
  final effectiveProvider = !isNewUser && provider == 'firebase'
      ? stringFromFirebase(data?['provider'], provider)
      : provider;

  userSettings.value = settings;
  garageCars.value = garage;

  if (!isNewUser && userBanIsActive(data)) {
    return AppUser(
      uid: firebaseUser.uid,
      name: name,
      username: stringFromFirebase(data?['username'], rawUsername),
      email: emailOverride ?? firebaseUser.email ?? '',
      photoUrl: photoUrl,
      bio: bio,
      avatarPath: avatarPath,
      role: role,
      verified: verified,
      globalChatModerator: globalChatModerator,
      moderatorCountryCodes: moderatorCountryCodes,
      city: city,
      country: country,
      banned: true,
      bannedUntilMillis: existingBannedUntilMillis,
      banReason: existingBanReason,
    );
  }

  final username = await reserveUsernameForCurrentUser(
    preferredUsername: boundedProfileUsername(rawUsername),
    previousUsername: data?['username'] as String?,
    allowFallback: true,
  );

  final firebaseData = <String, Object?>{
    'uid': firebaseUser.uid,
    'name': name,
    'username': username,
    'usernameKey': usernameKey(username),
    'email': emailOverride ?? firebaseUser.email ?? '',
    'photoUrl': photoUrl,
    'bio': bio,
    'avatarPath': avatarPath,
    if (isNewUser) 'city': city,
    if (isNewUser) 'country': country,
    'settings': settings.toFirebase(),
    'instagram': settings.instagram.trim(),
    'tiktok': settings.tiktok.trim(),
    'telegram': settings.telegram.trim(),
    'reviewNotifications': settings.reviewNotifications,
    'likeNotifications': settings.likeNotifications,
    'commentNotifications': settings.commentNotifications,
    'newSpotNotifications': settings.newSpotNotifications,
    'newMessageNotifications': settings.newMessageNotifications,
    'xpNotifications': settings.xpNotifications,
    'friendAtSpotNotifications': settings.friendAtSpotNotifications,
    'friendLiveShareNotifications': settings.friendLiveShareNotifications,
    'publicProfile': settings.publicProfile,
    'showGarage': settings.showGarage,
    'garage': garage.map((car) => car.toFirebase()).toList(),
    'provider': effectiveProvider,
    'telegramUsername': telegramUsername ?? data?['telegramUsername'],
    'deviceIds': FieldValue.arrayUnion(appDeviceIds),
    'lastDeviceId': appDeviceId,
    'lastDevicePlatform': Platform.operatingSystem,
    'lastDeviceSeenAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (isNewUser) {
    firebaseData['role'] = roleName(role);
    firebaseData['verified'] = verified;
    firebaseData['banned'] = false;
    firebaseData['deleted'] = false;
    firebaseData['createdAt'] = FieldValue.serverTimestamp();
  }

  await userRef.debugSet(firebaseData, SetOptions(merge: true));

  return AppUser(
    uid: firebaseUser.uid,
    name: name,
    username: username,
    email: emailOverride ?? firebaseUser.email ?? '',
    photoUrl: photoUrl,
    bio: bio,
    avatarPath: avatarPath,
    role: role,
    verified: verified,
    globalChatModerator: globalChatModerator,
    moderatorCountryCodes: moderatorCountryCodes,
    city: city,
    country: country,
    banned: data?['banned'] == true,
    bannedUntilMillis: existingBannedUntilMillis,
    banReason: existingBanReason,
  );
}

bool isTransientFirebaseAuthNetworkError(Object error) {
  final text = error.toString().toLowerCase();
  if (error is SocketException || error is TimeoutException) {
    return true;
  }

  if (error is FirebaseException) {
    final code = error.code.toLowerCase();
    if (code == 'network-request-failed' || code == 'unknown') {
      return true;
    }
  }

  return text.contains('i/o error during system call') ||
      text.contains('software caused connection abort') ||
      text.contains('connection reset') ||
      text.contains('connection aborted') ||
      text.contains('connection closed') ||
      text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('timed out') ||
      text.contains('timeout');
}

Future<User> signInWithCustomTokenRetrying(String firebaseToken) async {
  Object? lastError;

  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 700 * attempt * attempt));
      }

      final credential = await FirebaseAuth.instance
          .signInWithCustomToken(firebaseToken)
          .timeout(const Duration(seconds: 20));
      final user = credential.user;
      if (user != null) {
        return user;
      }

      throw Exception('Firebase login finished without a user.');
    } catch (error, stack) {
      lastError = error;
      debugPrint('Firebase custom-token sign-in attempt ${attempt + 1} failed');
      debugPrint('$error');
      debugPrint('$stack');

      final alreadySignedInUser = FirebaseAuth.instance.currentUser;
      if (alreadySignedInUser != null) {
        return alreadySignedInUser;
      }

      if (!isTransientFirebaseAuthNetworkError(error) || attempt == 2) {
        rethrow;
      }
    }
  }

  throw Exception('Firebase login failed. Last error: $lastError');
}

Future<AppUser> signInWithTelegramAndSaveUser({
  NewUserNicknameRequester? requestNewUserNickname,
}) async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check setup first.',
    );
  }

  final baseUrls = telegramAuthBaseUrls
      .map((url) => url.trim())
      .where(
        (url) =>
            url.isNotEmpty && !url.contains('YOUR_CCS_TELEGRAM_AUTH_BACKEND'),
      )
      .toSet()
      .toList();

  if (baseUrls.isEmpty) {
    throw Exception(
      'Telegram backend URL is not set. Deploy telegram_auth_server first.',
    );
  }

  String? baseUrl;
  Map<String, dynamic>? startData;
  Object? lastStartError;

  for (final candidateBaseUrl in baseUrls) {
    try {
      debugPrint('Trying Telegram auth backend: $candidateBaseUrl');
      final candidateStartData = await getJsonFromUrl(
        '$candidateBaseUrl/api/telegram-start',
      ).timeout(const Duration(seconds: 12));

      final candidateSessionId = stringFromFirebase(
        candidateStartData['sessionId'],
        '',
      );
      final candidateLoginUrl = stringFromFirebase(
        candidateStartData['loginUrl'],
        '',
      );

      if (candidateSessionId.isEmpty || candidateLoginUrl.isEmpty) {
        throw Exception('Telegram backend returned an invalid login session.');
      }

      baseUrl = candidateBaseUrl;
      startData = candidateStartData;
      break;
    } catch (error, stack) {
      lastStartError = error;
      debugPrint('Telegram auth backend failed: $candidateBaseUrl');
      debugPrint('$error');
      debugPrint('$stack');
    }
  }

  if (baseUrl == null || startData == null) {
    throw Exception(
      'Could not reach Telegram login server. Try switching Wi-Fi/mobile data '
      'or update the app. Last error: $lastStartError',
    );
  }

  final sessionId = stringFromFirebase(startData['sessionId'], '');
  final loginUrl = stringFromFirebase(startData['loginUrl'], '');

  final opened = await launchUrl(
    Uri.parse(loginUrl),
    mode: LaunchMode.externalApplication,
  );

  if (!opened) {
    throw Exception('Could not open Telegram login page.');
  }

  Map<String, dynamic>? completeData;
  Object? lastStatusError;
  var consecutiveStatusErrors = 0;

  for (var attempt = 0; attempt < 90; attempt++) {
    await Future.delayed(const Duration(seconds: 2));

    try {
      final statusData = await getJsonFromUrl(
        '$baseUrl/api/telegram-status?sessionId=${Uri.encodeComponent(sessionId)}',
      ).timeout(const Duration(seconds: 12));
      consecutiveStatusErrors = 0;
      final status = stringFromFirebase(statusData['status'], 'pending');

      if (status == 'complete') {
        completeData = statusData;
        break;
      }

      if (status == 'error') {
        throw Exception(
          stringFromFirebase(statusData['message'], 'Telegram login failed.'),
        );
      }
    } catch (error, stack) {
      lastStatusError = error;
      consecutiveStatusErrors += 1;
      debugPrint('Telegram auth status check failed: $baseUrl');
      debugPrint('$error');
      debugPrint('$stack');

      if (consecutiveStatusErrors >= 5) {
        throw Exception(
          'Telegram login server became unreachable. Try switching Wi-Fi/mobile '
          'data and try again. Last error: $lastStatusError',
        );
      }
    }
  }

  if (completeData == null) {
    throw Exception(
      lastStatusError == null
          ? 'Telegram login timed out. Try again.'
          : 'Telegram login timed out. Last error: $lastStatusError',
    );
  }

  final firebaseToken = stringFromFirebase(completeData['firebaseToken'], '');
  final telegramData = mapFromFirebase(completeData['telegram']);

  if (firebaseToken.isEmpty) {
    throw Exception('Telegram backend did not return a Firebase token.');
  }

  final firebaseUser = await signInWithCustomTokenRetrying(firebaseToken);

  final telegramUsername = stringFromFirebase(telegramData['username'], '');
  final firstName = stringFromFirebase(telegramData['first_name'], '');
  final lastName = stringFromFirebase(telegramData['last_name'], '');
  final fullName = ('$firstName $lastName').trim();
  final telegramId = stringFromFirebase(telegramData['id'], firebaseUser.uid);
  final photoUrl = stringFromFirebase(telegramData['photo_url'], '');
  final fallbackUsername = telegramUsername.isNotEmpty
      ? telegramUsername
      : 'telegram_$telegramId';
  final newUserUsernameOverride = await usernameOverrideForNewFirebaseUser(
    firebaseUser: firebaseUser,
    fallbackUsername: fallbackUsername,
    requestNewUserNickname: requestNewUserNickname,
  );

  setCurrentUser(
    await saveFirebaseUser(
      firebaseUser,
      provider: 'telegram',
      displayNameOverride: fullName.isEmpty ? fallbackUsername : fullName,
      usernameOverride: newUserUsernameOverride ?? fallbackUsername,
      emailOverride: '',
      photoUrlOverride: photoUrl.isEmpty ? null : photoUrl,
      telegramUsername: fallbackUsername,
    ),
  );
  await initializeSpotCountryFiltersForUser(currentUser);
  startCurrentUserDocumentWatcher();
  if (!currentUser.banActive) {
    startFirebaseSpotSync();
    unawaited(startCurrentUserLikedSpotsSync());
    unawaited(initializePushNotificationsForCurrentUser());
    startNotificationCenterUnreadWatcher();
  }
  return currentUser;
}

Future<AppUser> signInWithEmailAndSaveUser(
  String email,
  String password,
) async {
  final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: email.trim(),
    password: password,
  );
  final user = credential.user;
  if (user == null) throw StateError('Sign-in did not return an account.');
  try {
    setCurrentUser(await saveFirebaseUser(user, provider: 'password'));
    await initializeSpotCountryFiltersForUser(currentUser);
    startCurrentUserDocumentWatcher();
    if (!currentUser.banActive) {
      startFirebaseSpotSync();
      unawaited(startCurrentUserLikedSpotsSync());
      unawaited(initializePushNotificationsForCurrentUser());
      startNotificationCenterUnreadWatcher();
    }
    return currentUser;
  } catch (_) {
    await FirebaseAuth.instance.signOut();
    rethrow;
  }
}

Future<AppUser> signInWithGoogleAndSaveUser({
  NewUserNicknameRequester? requestNewUserNickname,
}) async {
  if (!firebaseReady) {
    throw Exception(
      googleSignInSetupError ??
          'Firebase did not initialize on this device. Check google-services.json and Android setup.',
    );
  }

  if (googleSignInSetupError != null) {
    throw Exception(googleSignInSetupError);
  }

  if (!GoogleSignIn.instance.supportsAuthenticate()) {
    throw Exception('Google Sign-In is not supported on this platform.');
  }

  final googleUser = await GoogleSignIn.instance.authenticate();
  final googleAuth = googleUser.authentication;
  final idToken = googleAuth.idToken;

  if (idToken == null) {
    throw Exception('Google did not return an ID token.');
  }

  final credential = GoogleAuthProvider.credential(idToken: idToken);
  final userCredential = await FirebaseAuth.instance.signInWithCredential(
    credential,
  );
  final firebaseUser = userCredential.user;

  if (firebaseUser == null) {
    throw Exception('Firebase login finished without a user.');
  }

  final newUserUsernameOverride = await usernameOverrideForNewFirebaseUser(
    firebaseUser: firebaseUser,
    fallbackUsername: makeUsernameFromFirebaseUser(firebaseUser),
    requestNewUserNickname: requestNewUserNickname,
  );

  setCurrentUser(
    await saveFirebaseUser(
      firebaseUser,
      provider: 'google',
      usernameOverride: newUserUsernameOverride,
    ),
  );
  await initializeSpotCountryFiltersForUser(currentUser);
  startCurrentUserDocumentWatcher();
  if (!currentUser.banActive) {
    startFirebaseSpotSync();
    unawaited(startCurrentUserLikedSpotsSync());
    unawaited(initializePushNotificationsForCurrentUser());
    startNotificationCenterUnreadWatcher();
  }
  return currentUser;
}

Future<AppUser> signInWithAppleAndSaveUser({
  NewUserNicknameRequester? requestNewUserNickname,
}) async {
  if (!firebaseReady) {
    throw StateError('Firebase is unavailable. Please retry.');
  }
  final session = FirebaseAuth.instance;
  final credential = await session.signInWithProvider(appleAuthProvider());
  final user = credential.user;
  if (user == null) {
    throw StateError('Apple sign-in did not return an account.');
  }
  try {
    final nickname = await usernameOverrideForNewFirebaseUser(
      firebaseUser: user,
      // Never suggest the random Hide My Email relay address as a public name.
      fallbackUsername: 'ccs_driver',
      requestNewUserNickname: requestNewUserNickname,
    );
    setCurrentUser(
      await saveFirebaseUser(
        user,
        provider: 'apple',
        usernameOverride: nickname,
      ),
    );
    await initializeSpotCountryFiltersForUser(currentUser);
    startCurrentUserDocumentWatcher();
    if (!currentUser.banActive) {
      startFirebaseSpotSync();
      unawaited(startCurrentUserLikedSpotsSync());
      unawaited(initializePushNotificationsForCurrentUser());
      startNotificationCenterUnreadWatcher();
    }
    return currentUser;
  } catch (_) {
    await session.signOut();
    rethrow;
  }
}
