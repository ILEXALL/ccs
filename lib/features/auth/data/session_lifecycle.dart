import 'package:ccs_app/features/auth/models/app_user_document.dart'
    show appUserFromCurrentUserDocument;
import 'dart:async';
import 'package:ccs_app/features/auth/navigation/sign_out_navigation.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:ccs_app/core/firestore/firestore_usage_estimate.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show firestoreDebugTracker;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show liveLocationBackgroundChannel;
import 'package:ccs_app/features/auth/data/auth_preferences.dart'
    show saveRememberMePreference;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show
        accountSignOutInProgress,
        accountSigningOut,
        currentUser,
        setCurrentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' show AppUser;
import 'package:ccs_app/features/events/data/event_reminders.dart'
    show
        startTemporarySpotTodayNotificationScheduler,
        stopTemporarySpotTodayNotificationScheduler;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show stopIncomingFriendRequestCountStream;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show updateCurrentUserOnlinePresence;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show
        chatUnreadCountsByChatId,
        inAppBadges,
        notificationCenterUnreadCount,
        notificationCenterUnreadCountsBySource;
import 'package:ccs_app/features/notifications/data/push_notifications.dart'
    show
        initializePushNotificationsForCurrentUser,
        pushInitializationFuture,
        pushInitializationUid,
        unregisterPushTokenForCurrentUser;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show
        adminNotificationCenterUnreadSubscription,
        friendLocationNotificationCenterUnreadSubscription,
        notificationCenterUnreadRefreshDebounce,
        notificationCenterUnreadSubscription,
        startNotificationCenterUnreadWatcher;
import 'package:ccs_app/features/profile/data/profile_state.dart'
    show garageCars, userSettings;
import 'package:ccs_app/features/profile/models/user_settings.dart'
    show defaultUserSettings;
import 'package:ccs_app/features/spots/data/saved_spots.dart'
    show saveSavedSpotIds;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show
        saveSpotCountryFiltersPreference,
        spotCountryFilters,
        spotCountryFiltersFromUserData;
import 'package:ccs_app/features/spots/data/spot_likes.dart'
    show startCurrentUserLikedSpotsSync, stopCurrentUserLikedSpotsSync;
import 'package:ccs_app/features/spots/data/spot_reviews.dart'
    show spotCommentsSessionCache;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show
        adminReviewSpotSubscription,
        adminReviewSpotSyncRequested,
        invalidateSpotSync,
        spotSyncCancellation,
        startAdminReviewSpotSync,
        startFirebaseSpotSync;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show
        currentSpotSyncScope,
        firebaseSpotCacheBySource,
        spotSyncScope,
        spotSyncSubscriptions;
import 'package:ccs_app/shared/models/countries.dart' show spotCountryKey;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
currentUserDocumentSubscription;

Future<void> stopCurrentUserAppServicesForAccessBlock() async {
  invalidateSpotSync();
  stopTemporarySpotTodayNotificationScheduler();
  for (final subscription in spotSyncSubscriptions) {
    await subscription.cancel();
  }
  spotSyncSubscriptions.clear();
  await adminReviewSpotSubscription?.cancel();
  adminReviewSpotSubscription = null;
  adminReviewSpotSyncRequested = false;
  firebaseSpotCacheBySource.clear();
  await notificationCenterUnreadSubscription?.cancel();
  notificationCenterUnreadSubscription = null;
  await adminNotificationCenterUnreadSubscription?.cancel();
  adminNotificationCenterUnreadSubscription = null;
  await friendLocationNotificationCenterUnreadSubscription?.cancel();
  friendLocationNotificationCenterUnreadSubscription = null;
  notificationCenterUnreadRefreshDebounce?.cancel();
  notificationCenterUnreadRefreshDebounce = null;
  notificationCenterUnreadCountsBySource.clear();
  notificationCenterUnreadCount.value = 0;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    chatUnreadCountsByChatId.value = const <String, int>{};
  });
  await stopCurrentUserLikedSpotsSync();
}

Timer? _profileWatcherRetry;

int _profileWatcherGeneration = 0;

int _profileWatcherRetryAttempt = 0;

void startCurrentUserDocumentWatcher() {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final generation = ++_profileWatcherGeneration;
  _profileWatcherRetry?.cancel();
  _profileWatcherRetry = null;
  unawaited(currentUserDocumentSubscription?.cancel());
  currentUserDocumentSubscription = null;

  if (firebaseUser == null) {
    return;
  }

  void retryProfileWatcher() {
    if (generation != _profileWatcherGeneration ||
        FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid ||
        _profileWatcherRetry != null) {
      return;
    }
    final delay = math.min(
      60,
      2 * (1 << math.min(_profileWatcherRetryAttempt++, 5)),
    );
    _profileWatcherRetry = Timer(Duration(seconds: delay), () {
      _profileWatcherRetry = null;
      if (generation == _profileWatcherGeneration &&
          FirebaseAuth.instance.currentUser?.uid == firebaseUser.uid) {
        startCurrentUserDocumentWatcher();
      }
    });
  }

  bool receivedServerProfile = false;
  final profileReadEstimate = ServerReadEstimate();

  currentUserDocumentSubscription = usersCollection()
      .doc(firebaseUser.uid)
      .snapshots(includeMetadataChanges: true)
      .listen(
        (snapshot) {
          if (generation != _profileWatcherGeneration ||
              !snapshot.exists ||
              snapshot.id != FirebaseAuth.instance.currentUser?.uid) {
            return;
          }
          if (snapshot.metadata.isFromCache && receivedServerProfile) return;
          if (!snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites) {
            receivedServerProfile = true;
            _profileWatcherRetryAttempt = 0;
          }
          firestoreDebugTracker.recordRead(
            'startup: current user document listener',
            profileReadEstimate.observe(
              {snapshot.id: snapshot.data()},
              fromCache: snapshot.metadata.isFromCache,
              pendingWrites: snapshot.metadata.hasPendingWrites,
            ),
          );

          final wasBanActive = currentUser.banActive;
          final hadVerifiedOnlySpotAccess = currentUserCanUseVerifiedOnlySpots;
          final previousRole = currentUser.role;
          final previousModeratorCountries = currentUser.moderatorCountryCodes;
          final nextUser = appUserFromCurrentUserDocument(snapshot);
          setCurrentUser(nextUser);
          final snapshotData = snapshot.data();
          if (snapshotData != null &&
              snapshotData['spotCountryFilters'] is Iterable) {
            final remoteCountryFilters = spotCountryFiltersFromUserData(
              snapshotData,
            );
            final currentKeys = spotCountryFilters.value
                .map(spotCountryKey)
                .toSet();
            final remoteKeys = remoteCountryFilters.map(spotCountryKey).toSet();
            if (currentKeys.length != remoteKeys.length ||
                !currentKeys.containsAll(remoteKeys)) {
              spotCountryFilters.value = remoteCountryFilters;
              unawaited(
                saveSpotCountryFiltersPreference(
                  nextUser.uid,
                  remoteCountryFilters,
                ),
              );
            }
          }
          final verifiedOnlySpotAccessChanged =
              hadVerifiedOnlySpotAccess != currentUserCanUseVerifiedOnlySpots;
          final moderatorScopeChanged =
              previousRole != nextUser.role ||
              previousModeratorCountries.length !=
                  nextUser.moderatorCountryCodes.length ||
              !previousModeratorCountries.containsAll(
                nextUser.moderatorCountryCodes,
              );
          if (moderatorScopeChanged && adminReviewSpotSyncRequested) {
            startAdminReviewSpotSync();
          }
          startTemporarySpotTodayNotificationScheduler();

          if (nextUser.banActive) {
            unawaited(stopCurrentUserAppServicesForAccessBlock());
          } else if (wasBanActive) {
            startFirebaseSpotSync();
            unawaited(startCurrentUserLikedSpotsSync());
            unawaited(initializePushNotificationsForCurrentUser());
            startNotificationCenterUnreadWatcher();
          } else if (verifiedOnlySpotAccessChanged ||
              spotSyncScope != currentSpotSyncScope) {
            // Compare against the running feed, not only the previous profile:
            // another startup path may already have updated currentUser.
            // The new scope gets a complete authoritative approved-spot feed.
            startFirebaseSpotSync(forceFullRefresh: true);
          }
        },
        onError: (Object error) {
          debugPrint('Current user watcher failed: $error');
          retryProfileWatcher();
        },
        onDone: retryProfileWatcher,
      );
}

Future<void> signOutCurrentAccount() async {
  if (accountSignOutInProgress) return;
  accountSignOutInProgress = true;
  accountSigningOut.value = true;
  _profileWatcherGeneration++;
  _profileWatcherRetry?.cancel();
  _profileWatcherRetry = null;
  _profileWatcherRetryAttempt = 0;
  invalidateSpotSync();
  stopTemporarySpotTodayNotificationScheduler();
  inAppBadges.stop();
  notificationCenterUnreadRefreshDebounce?.cancel();
  final subscriptions = <StreamSubscription?>[
    currentUserDocumentSubscription,
    adminReviewSpotSubscription,
    notificationCenterUnreadSubscription,
    adminNotificationCenterUnreadSubscription,
    friendLocationNotificationCenterUnreadSubscription,
  ];
  currentUserDocumentSubscription = null;
  adminReviewSpotSubscription = null;
  notificationCenterUnreadSubscription = null;
  adminNotificationCenterUnreadSubscription = null;
  friendLocationNotificationCenterUnreadSubscription = null;
  // Detach authenticated widgets before clearing their data and streams.
  await WidgetsBinding.instance.endOfFrame;
  Future<void> bestEffort(Future<void> future) async {
    try {
      await future.timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('Sign-out cleanup: $error');
    }
  }

  try {
    await Future.wait([
      for (final subscription in subscriptions)
        if (subscription != null) bestEffort(subscription.cancel()),
      bestEffort(stopIncomingFriendRequestCountStream()),
      bestEffort(stopCurrentUserLikedSpotsSync()),
      bestEffort(spotSyncCancellation),
      bestEffort(saveRememberMePreference(false)),
      bestEffort(unregisterPushTokenForCurrentUser()),
      bestEffort(updateCurrentUserOnlinePresence(isOnline: false)),
      bestEffort(liveLocationBackgroundChannel.invokeMethod<void>('stop')),
      if (FirebaseAuth.instance.currentUser != null)
        bestEffort(
          liveLocationsCollection()
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .delete(),
        ),
    ]);
    await FirebaseAuth.instance.signOut();
    await bestEffort(GoogleSignIn.instance.signOut());
  } catch (_) {
    accountSignOutInProgress = false;
    accountSigningOut.value = false;
    rethrow;
  }
  pushInitializationUid = null;
  pushInitializationFuture = null;
  adminReviewSpotSyncRequested = false;
  firebaseSpotCacheBySource.clear();
  notificationCenterUnreadCountsBySource.clear();
  notificationCenterUnreadCount.value = 0;
  chatUnreadCountsByChatId.value = const <String, int>{};
  spotCommentsSessionCache.clear();
  showSignedOutScreen();
  setCurrentUser(
    const AppUser(
      uid: '',
      name: '',
      username: '',
      email: '',
      role: UserRole.user,
      verified: false,
      globalChatModerator: false,
      city: '',
      country: '',
    ),
  );

  reviewSpots.value = [];
  submittedSpots.value = [];
  savedSpots.value = [];
  spotCountryFilters.value = <String>{};
  unawaited(saveSavedSpotIds());
  userSettings.value = defaultUserSettings();
  garageCars.value = const [];
}
