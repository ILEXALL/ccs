import 'package:ccs_app/features/profile/data/profile_fields.dart'
    show saveCurrentUserFields;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart' show maxGaragePhotos;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, setCurrentUser;
import 'package:ccs_app/features/auth/data/usernames.dart'
    show reserveUsernameForCurrentUser, usernameKey;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/notifications/data/community_notifications.dart'
    show communityPushRecipientCache, communityPushRecipientCacheAtMillis;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show scheduleNotificationCenterUnreadRefresh;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show garageCars, userSettings;
import 'package:ccs_app/features/profile/models/profile_validation.dart'
    show profileRegionIsComplete, requiredRegionMessage;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/models/user_profile.dart'
    show UserProfileData;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show UserSettingsData;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show syncXpWithServer;
import 'package:ccs_app/shared/media/entity_photos.dart'
    show uploadGarageCarPhoto, uploadUserAvatarPhoto;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/countries.dart'
    show canonicalSpotCountryName;

Future<void> saveCurrentUserSettings(UserSettingsData settings) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    userSettings.value = settings;
    return;
  }

  userSettings.value = settings;

  await usersCollection().doc(firebaseUser.uid).debugSet({
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
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> saveProfileToFirebase(UserProfileData profile) async {
  if (!profileRegionIsComplete(profile.city, profile.country)) {
    throw ArgumentError(requiredRegionMessage);
  }
  final cityCountry = [
    profile.city.trim(),
    canonicalSpotCountryName(profile.country),
  ];
  final previousUsername = currentUser.username;
  final cleanUsername = await reserveUsernameForCurrentUser(
    preferredUsername: profile.username,
    previousUsername: previousUsername,
  );

  var nextPhotoUrl = currentUser.photoUrl;
  String? nextAvatarPath = profile.avatarPath;

  if (localFileExists(profile.avatarPath)) {
    nextPhotoUrl = await uploadUserAvatarPhoto(
      userId: currentUser.uid,
      localPhotoPath: profile.avatarPath!,
    );
    nextAvatarPath = null;
  } else if (isNetworkUrl(profile.avatarPath)) {
    nextPhotoUrl = profile.avatarPath;
    nextAvatarPath = null;
  }

  final nextSettings = userSettings.value.copyWith(
    instagram: profile.instagram.trim(),
    tiktok: profile.tiktok.trim(),
    telegram: profile.telegram.trim(),
  );
  await saveCurrentUserFields({
    'username': cleanUsername,
    'usernameKey': usernameKey(cleanUsername),
    'bio': profile.bio,
    'photoUrl': nextPhotoUrl,
    'avatarPath': nextAvatarPath,
    'city': cityCountry[0],
    'country': cityCountry[1],
    'settings': nextSettings.toFirebase(),
    'instagram': nextSettings.instagram.trim(),
    'tiktok': nextSettings.tiktok.trim(),
    'telegram': nextSettings.telegram.trim(),
  });
  setCurrentUser(
    AppUser(
      uid: currentUser.uid,
      name: currentUser.name,
      username: cleanUsername,
      email: currentUser.email,
      photoUrl: nextPhotoUrl,
      bio: profile.bio,
      avatarPath: nextAvatarPath,
      role: currentUser.role,
      verified: currentUser.verified,
      globalChatModerator: currentUser.globalChatModerator,
      moderatorCountryCodes: currentUser.moderatorCountryCodes,
      city: cityCountry[0],
      country: cityCountry[1],
    ),
  );

  userSettings.value = nextSettings;
  unawaited(syncXpWithServer({'action': 'sync_me'}));
}

Future<void> saveGarageToFirebase(List<GarageCar> cars) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uploadedCars = <GarageCar>[];

  for (var carIndex = 0; carIndex < cars.length; carIndex++) {
    final car = cars[carIndex];
    final uploadedPhotoPaths = <String>[];
    final photoSources = car.galleryPhotos.take(maxGaragePhotos).toList();

    for (var photoIndex = 0; photoIndex < photoSources.length; photoIndex++) {
      final source = photoSources[photoIndex];

      if (firebaseUser != null && localFileExists(source)) {
        final uploadedPhotoUrl = await uploadGarageCarPhoto(
          userId: firebaseUser.uid,
          carIndex: carIndex,
          photoIndex: photoIndex,
          localPhotoPath: source,
        );
        uploadedPhotoPaths.add(uploadedPhotoUrl);
      } else if (source.trim().isNotEmpty) {
        uploadedPhotoPaths.add(source.trim());
      }
    }

    uploadedCars.add(
      GarageCar(
        name: car.name,
        description: car.description,
        buildType: car.buildType,
        useType: car.useType,
        tags: car.tags,
        photoPath: uploadedPhotoPaths.isEmpty ? null : uploadedPhotoPaths.first,
        photoPaths: uploadedPhotoPaths,
      ),
    );
  }

  await saveCurrentUserFields({
    'garage': uploadedCars.map((car) => car.toFirebase()).toList(),
  });

  // Publish only after the account write succeeds. This keeps the global
  // garage state consistent when a delete/edit upload fails and the UI rolls
  // back to the previous list.
  garageCars.value = uploadedCars;
  unawaited(syncXpWithServer({'action': 'sync_me'}));
}

Future<void> saveSettingsToFirebase(UserSettingsData settings) async {
  userSettings.value = settings;
  communityPushRecipientCache.clear();
  communityPushRecipientCacheAtMillis.clear();

  await saveCurrentUserFields({
    'settings': settings.toFirebase(),
    'instagram': settings.instagram.trim(),
    'tiktok': settings.tiktok.trim(),
    'telegram': settings.telegram.trim(),
    // Keep flat copies too so older backend/functions or admin tools that read
    // notification settings directly from the user document do not miss changes.
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
  });

  scheduleNotificationCenterUnreadRefresh();
  unawaited(syncXpWithServer({'action': 'sync_me'}));
}
