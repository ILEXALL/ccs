import 'spot_account_hooks.dart';
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show spotSyncSubscriptions;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show firebaseSpotCacheBySource;
import 'package:ccs_app/features/spots/models/spot_version.dart'
    show spotCacheKey;
import 'package:ccs_app/features/spots/models/spot_version.dart'
    show spotVersionFreshnessMillis;
import 'package:ccs_app/features/spots/models/spot_version.dart'
    show preferredSpotVersion;
import 'package:ccs_app/features/spots/data/spot_feed_projection.dart'
    show publishFirebaseSpotCaches;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show spotSyncGeneration;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show spotSyncScope;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show spotSourcesWithServerSnapshot;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show currentSpotSyncScope;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show spotSyncIsCurrent;
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show spotsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugWriteBatchExtension,
        trackedQueryGet,
        trackedQuerySnapshots;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, setCurrentUser;
import 'package:ccs_app/features/auth/models/app_user_document.dart'
    show appUserFromCurrentUserDocument;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show syncActiveTemporarySpotForumTopics;
import 'package:ccs_app/features/community/groups/data/group_spots.dart'
    show groupSpotCancellation, startGroupSpotSync, stopGroupSpotSync;
import 'package:ccs_app/features/events/data/event_reminders.dart'
    show
        notifyAllUsersAboutTemporarySpotsToday,
        startTemporarySpotTodayNotificationScheduler;
import 'package:ccs_app/features/spots/data/spot_cache.dart'
    show approvedSpotIsVisibleForCurrentUser, saveApprovedSpotsToLocalCache;
import 'package:ccs_app/features/spots/data/spot_cache_loader.dart'
    show loadApprovedSpotsFromLocalCache;
import 'package:ccs_app/features/spots/data/spot_queries.dart'
    show approvedSpotsForCurrentUserQuery;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show spotStatusName;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;

const int firebaseApprovedSpotsListenLimit = 250;

const int firebaseTemporarySpotsListenLimit = 500;

const int firebaseMySpotsListenLimit = 100;

const int firebaseAdminReviewSpotsListenLimit = 250;

StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
adminReviewSpotSubscription;

bool adminReviewSpotSyncRequested = false;

const String localImmediateSpotCacheSource = 'local immediate';

void upsertSpotIntoLocalImmediateCache(CarSpot spot) {
  final key = spotCacheKey(spot);
  for (final source in firebaseSpotCacheBySource.values) {
    final existing = source[key];
    if (existing != null) spot = preferredSpotVersion(existing, spot);
  }
  final nextSource = <String, CarSpot>{
    ...(firebaseSpotCacheBySource[localImmediateSpotCacheSource] ??
        const <String, CarSpot>{}),
    key: spot,
  };

  firebaseSpotCacheBySource[localImmediateSpotCacheSource] = nextSource;
  publishFirebaseSpotCaches();

  if (approvedSpotIsVisibleForCurrentUser(spot)) {
    final nextApproved = <String, CarSpot>{
      ...(firebaseSpotCacheBySource['approved'] ?? const <String, CarSpot>{}),
      key: spot,
    };
    firebaseSpotCacheBySource['approved'] = nextApproved;
    publishFirebaseSpotCaches();
    unawaited(saveApprovedSpotsToLocalCache());
  }
}

void removeSpotFromLocalImmediateCache(CarSpot spot) {
  final key = spotCacheKey(spot);
  var changed = false;

  for (final sourceEntry in firebaseSpotCacheBySource.entries.toList()) {
    if (!sourceEntry.value.containsKey(key)) {
      continue;
    }

    final nextSource = <String, CarSpot>{...sourceEntry.value}..remove(key);
    if (nextSource.isEmpty) {
      firebaseSpotCacheBySource.remove(sourceEntry.key);
    } else {
      firebaseSpotCacheBySource[sourceEntry.key] = nextSource;
    }
    changed = true;
  }

  if (changed) {
    publishFirebaseSpotCaches();
    unawaited(saveApprovedSpotsToLocalCache());
  }
}

void _applySpotFeedSnapshot(
  String source,
  QuerySnapshot<Map<String, dynamic>> snapshot,
) {
  final parsedSpots = snapshot.docs.map(CarSpot.fromFirestore).toList();
  final incoming = {for (final spot in parsedSpots) spotCacheKey(spot): spot};
  final authoritative =
      !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites;

  // Once the server has answered, an offline cache replay must not replace
  // current fields (country, expiry, status) with an older device-local copy.
  if (snapshot.metadata.isFromCache &&
      !snapshot.metadata.hasPendingWrites &&
      spotSourcesWithServerSnapshot.contains(source)) {
    return;
  }

  // Offline query snapshots may contain only part of the saved feed.
  // Only a complete server snapshot may remove cached records.
  final nextSource = authoritative
      ? incoming
      : <String, CarSpot>{...?firebaseSpotCacheBySource[source]};
  if (!authoritative) {
    for (final entry in incoming.entries) {
      final existing = nextSource[entry.key];
      nextSource[entry.key] = existing == null
          ? entry.value
          : preferredSpotVersion(existing, entry.value);
    }
  }
  firebaseSpotCacheBySource[source] = nextSource;
  // Cache-only events cannot invalidate an in-flight server refresh. Pending
  // writes still advance the revision so the refresh cannot undo a local edit.
  if (!snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
    _spotFeedRevisions[source] = (_spotFeedRevisions[source] ?? 0) + 1;
  }
  if (authoritative) {
    _failedSpotSources.remove(source);
    spotSourcesWithServerSnapshot.add(source);
    _spotFeedServerReceivedAt[source] = DateTime.now();
    final ready = _spotFeedServerReady[source];
    if (ready != null && !ready.isCompleted) ready.complete();
    final immediate = firebaseSpotCacheBySource[localImmediateSpotCacheSource];
    if (immediate != null) {
      for (final spot in parsedSpots) {
        final key = spotCacheKey(spot);
        final local = immediate[key];
        if (local != null &&
            spotVersionFreshnessMillis(spot) >=
                spotVersionFreshnessMillis(local)) {
          immediate.remove(key);
        }
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          immediate.remove(change.doc.id);
        }
      }
    }
    if (_failedSpotSources.isEmpty &&
        spotSourcesWithServerSnapshot.containsAll([
          'approved',
          'my submissions',
        ])) {
      _spotSyncRetryAttempt = 0;
      spotSyncRetryTimer?.cancel();
      spotSyncRetryTimer = null;
    }
  }
  publishFirebaseSpotCaches();
  if (authoritative && (source == 'approved' || source == 'my submissions')) {
    unawaited(syncActiveTemporarySpotForumTopics());
  }
  if (source == 'approved' && authoritative) {
    unawaited(saveApprovedSpotsToLocalCache());
    if (userRoleIsStaff(currentUser.role)) {
      unawaited(
        notifyAllUsersAboutTemporarySpotsToday(
          parsedSpots.where((spot) => spot.isTemporary).toList(),
        ),
      );
    }
  }
}

void _listenToSpotQuery({
  required String source,
  required Query<Map<String, dynamic>> query,
  required int generation,
  required String scope,
}) {
  _spotFeedServerReady.putIfAbsent(source, () => Completer<void>());
  final subscription =
      trackedQuerySnapshots(
        'spots listener: $source',
        query,
        includeMetadataChanges: true,
      ).listen(
        (snapshot) {
          if (!spotSyncIsCurrent(generation, scope)) return;
          _applySpotFeedSnapshot(source, snapshot);
        },
        onError: (Object error, StackTrace stack) {
          if (!spotSyncIsCurrent(generation, scope)) return;
          _failedSpotSources.add(source);
          spotSourcesWithServerSnapshot.remove(source);
          debugPrint('Spot listener failed for $source: $error');
          debugPrint('$stack');
          _scheduleSpotSyncRetry(generation, scope);
        },
        onDone: () {
          if (!spotSyncIsCurrent(generation, scope)) return;
          _failedSpotSources.add(source);
          spotSourcesWithServerSnapshot.remove(source);
          _scheduleSpotSyncRetry(generation, scope);
        },
      );
  spotSyncSubscriptions.add(subscription);
}

void startApprovedSpotsLiveSync(int generation, String scope) {
  startGroupSpotSync(generation, scope);
  // No arbitrary document-ID limit: new and older verified spots must both
  // participate in the live feed and remain available to the map.
  _listenToSpotQuery(
    source: 'approved',
    query: approvedSpotsForCurrentUserQuery(),
    generation: generation,
    scope: scope,
  );
  _listenToSpotQuery(
    source: 'my submissions',
    query: spotsCollection()
        .where('visibility', isEqualTo: 'public')
        .where('addedByUid', isEqualTo: currentUser.uid),
    generation: generation,
    scope: scope,
  );
}

Future<void> stopAdminReviewSpotSync() async {
  adminReviewSpotSyncRequested = false;
  await adminReviewSpotSubscription?.cancel();
  adminReviewSpotSubscription = null;
  firebaseSpotCacheBySource.remove('admin review');
  publishFirebaseSpotCaches();
}

final Set<String> _spotCountryCodeBackfillsThisSession = <String>{};

Future<void> _backfillLegacySpotCountryCodes(Iterable<CarSpot> spots) async {
  if (currentUser.role != UserRole.admin) {
    return;
  }

  final missing = spots
      .where(
        (spot) =>
            spot.id.isNotEmpty &&
            spot.countryCode.trim().isEmpty &&
            spot.effectiveCountryCode.isNotEmpty &&
            !_spotCountryCodeBackfillsThisSession.contains(spot.id),
      )
      .take(400)
      .toList(growable: false);
  if (missing.isEmpty) {
    return;
  }

  _spotCountryCodeBackfillsThisSession.addAll(missing.map((spot) => spot.id));
  try {
    final batch = FirebaseFirestore.instance.batch();
    for (final spot in missing) {
      batch.debugUpdate(
        spotsCollection().doc(spot.id),
        {'countryCode': spot.effectiveCountryCode},
        'admin: legacy spot country code backfill',
      );
    }
    await batch.debugCommit();
  } catch (error, stack) {
    _spotCountryCodeBackfillsThisSession.removeAll(
      missing.map((spot) => spot.id),
    );
    debugPrint('Legacy spot country-code backfill failed: $error');
    debugPrint('$stack');
  }
}

void startAdminReviewSpotSync() {
  if (!userRoleIsStaff(currentUser.role)) {
    unawaited(stopAdminReviewSpotSync());
    return;
  }

  adminReviewSpotSyncRequested = true;

  unawaited(adminReviewSpotSubscription?.cancel());

  const adminReviewStatuses = <String>[
    'pending',
    'edited',
    'approved',
    'rejected',
  ];

  Query<Map<String, dynamic>> reviewQuery;
  if (currentUser.role == UserRole.admin) {
    reviewQuery = spotsCollection().where(
      'status',
      whereIn: adminReviewStatuses,
    );
  } else {
    final assignedCountries = currentUser.moderatorCountryCodes.toList()
      ..sort();
    if (assignedCountries.isEmpty) {
      adminReviewSpotSubscription = null;
      firebaseSpotCacheBySource['admin review'] = <String, CarSpot>{};
      publishFirebaseSpotCaches();
      return;
    }
    reviewQuery = spotsCollection().where(
      'countryCode',
      whereIn: assignedCountries.take(30).toList(growable: false),
    );
  }

  adminReviewSpotSubscription =
      trackedQuerySnapshots(
        'spots listener: admin review',
        reviewQuery.limit(firebaseAdminReviewSpotsListenLimit),
      ).listen(
        (snapshot) {
          final parsedSpots = snapshot.docs
              .map(CarSpot.fromFirestore)
              .where(
                (spot) =>
                    adminReviewStatuses.contains(spotStatusName(spot.status)),
              )
              .toList(growable: false);
          firebaseSpotCacheBySource['admin review'] = {
            for (final spot in parsedSpots) spotCacheKey(spot): spot,
          };
          publishFirebaseSpotCaches();
          if (currentUser.role == UserRole.admin) {
            unawaited(_backfillLegacySpotCountryCodes(parsedSpots));
          }
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('Admin review spot listener failed: $error');
          debugPrint('$stack');
        },
      );
}

Timer? spotSyncRetryTimer;

int _spotSyncRetryAttempt = 0;

final Set<String> _failedSpotSources = {};

final Map<String, int> _spotFeedRevisions = {};

final Map<String, DateTime> _spotFeedServerReceivedAt = {};

final Map<String, Completer<void>> _spotFeedServerReady = {};

bool spotFeedServerSnapshotIsFresh(DateTime? receivedAt, DateTime now) {
  if (receivedAt == null) return false;
  final age = now.difference(receivedAt);
  return !age.isNegative && age < const Duration(seconds: 30);
}

Future<void>? _spotRefreshInFlight;

String? _spotRefreshInFlightScope;

Future<void>? _spotSyncStartInFlight;

String? _spotSyncStartInFlightScope;

Future<void> spotSyncCancellation = Future<void>.value();

void invalidateSpotSync() {
  stopGroupSpotSync();
  final pending = <Future<void>>[spotSyncCancellation, groupSpotCancellation];
  spotSyncGeneration++;
  spotSyncRetryTimer?.cancel();
  spotSyncRetryTimer = null;
  spotSyncScope = null;
  spotSourcesWithServerSnapshot.clear();
  _failedSpotSources.clear();
  _spotFeedRevisions.clear();
  _spotFeedServerReceivedAt.clear();
  // Release waiters on an obsolete scope; their generation check prevents
  // applying data after a sign-out or access change.
  for (final ready in _spotFeedServerReady.values) {
    if (!ready.isCompleted) ready.complete();
  }
  _spotFeedServerReady.clear();
  _spotRefreshInFlight = null;
  _spotRefreshInFlightScope = null;
  _spotSyncStartInFlight = null;
  _spotSyncStartInFlightScope = null;
  for (final subscription in spotSyncSubscriptions) {
    pending.add(subscription.cancel());
  }
  spotSyncSubscriptions.clear();
  spotSyncCancellation = Future.wait(pending).then((_) {});
}

void _scheduleSpotSyncRetry(int generation, String scope) {
  if (!spotSyncIsCurrent(generation, scope) || spotSyncRetryTimer != null) {
    return;
  }
  final seconds = math.min(60, 2 * (1 << math.min(_spotSyncRetryAttempt, 5)));
  _spotSyncRetryAttempt++;
  spotSyncRetryTimer = Timer(Duration(seconds: seconds), () {
    spotSyncRetryTimer = null;
    if (!spotSyncIsCurrent(generation, scope)) return;
    restartSpotAccountWatcher();
    startFirebaseSpotSync(forceFullRefresh: true);
  });
}

void startFirebaseSpotSync({bool forceFullRefresh = false}) {
  if (FirebaseAuth.instance.currentUser?.uid != currentUser.uid ||
      currentUser.uid.isEmpty ||
      currentUser.banActive) {
    return;
  }
  final scope = currentSpotSyncScope;
  final scopeChanged = spotSyncScope != scope;
  if (!forceFullRefresh &&
      !scopeChanged &&
      _failedSpotSources.isEmpty &&
      spotSyncRetryTimer == null &&
      (spotSyncSubscriptions.isNotEmpty ||
          (_spotSyncStartInFlight != null &&
              _spotSyncStartInFlightScope == scope))) {
    return;
  }
  invalidateSpotSync();
  spotSyncScope = scope;
  if (scopeChanged) {
    _spotSyncRetryAttempt = 0;
    firebaseSpotCacheBySource.clear();
    // Notify both Map and Explore immediately when access changes.
    publishFirebaseSpotCaches();
    if (adminReviewSpotSyncRequested) startAdminReviewSpotSync();
  }
  startTemporarySpotTodayNotificationScheduler();
  final generation = spotSyncGeneration;
  final startup = _startCachedSpotSync(generation, scope, forceFullRefresh);
  _spotSyncStartInFlight = startup;
  _spotSyncStartInFlightScope = scope;
  unawaited(
    startup.whenComplete(() {
      if (identical(_spotSyncStartInFlight, startup)) {
        _spotSyncStartInFlight = null;
        _spotSyncStartInFlightScope = null;
      }
    }),
  );
}

Future<void> _startCachedSpotSync(
  int generation,
  String scope,
  bool forceFullRefresh,
) async {
  try {
    if (!forceFullRefresh &&
        !firebaseSpotCacheBySource.containsKey('approved')) {
      await loadApprovedSpotsFromLocalCache(
        generation: generation,
        scope: scope,
      );
    }
  } finally {
    // Never gate the live listeners on a successful network/delta request.
    if (spotSyncIsCurrent(generation, scope)) {
      startApprovedSpotsLiveSync(generation, scope);
    }
  }
}

Future<void> refreshFirebaseSpotsFromServer() async {
  // Refresh authorization before choosing the query: a stale public profile
  // must not keep a verified user on the public-only feed after manual refresh.
  final authUid = FirebaseAuth.instance.currentUser?.uid;
  if (authUid == null) return;
  final profile = await usersCollection()
      .doc(authUid)
      .debugGet(
        const GetOptions(source: Source.server),
        'spots refresh: server profile',
      )
      .timeout(const Duration(seconds: 20));
  if (FirebaseAuth.instance.currentUser?.uid != authUid || !profile.exists) {
    return;
  }
  setCurrentUser(appUserFromCurrentUserDocument(profile));
  if (currentUser.banActive) {
    await stopSpotAccountServices();
    return;
  }
  if (FirebaseAuth.instance.currentUser?.uid != currentUser.uid ||
      currentUser.uid.isEmpty ||
      currentUser.banActive) {
    return;
  }
  final existing = _spotRefreshInFlight;
  if (existing != null &&
      _spotRefreshInFlightScope == currentSpotSyncScope &&
      spotSyncScope == currentSpotSyncScope) {
    return existing;
  }
  if (spotSyncScope != currentSpotSyncScope ||
      spotSyncSubscriptions.isEmpty ||
      _failedSpotSources.isNotEmpty ||
      spotSyncRetryTimer != null) {
    startFirebaseSpotSync(forceFullRefresh: true);
  }
  // A newly attached listener already reads the full query. Wait for that
  // server result instead of issuing the same query again with get().
  await _spotSyncStartInFlight;
  final generation = spotSyncGeneration;
  final scope = currentSpotSyncScope;
  final refresh = _refreshSpotFeedsFromServer(
    generation,
    scope,
  ).timeout(const Duration(seconds: 20));
  _spotRefreshInFlight = refresh;
  _spotRefreshInFlightScope = scope;
  try {
    await refresh;
  } finally {
    if (identical(_spotRefreshInFlight, refresh)) {
      _spotRefreshInFlight = null;
      _spotRefreshInFlightScope = null;
    }
  }
}

Future<void> _refreshSpotFeedsFromServer(int generation, String scope) async {
  Future<void> refreshSource(
    String source,
    Query<Map<String, dynamic>> query,
  ) async {
    if (!spotSyncIsCurrent(generation, scope)) return;
    final ready = _spotFeedServerReady[source];
    if (!spotSourcesWithServerSnapshot.contains(source) && ready != null) {
      await ready.future;
      return;
    }
    if (!_failedSpotSources.contains(source) &&
        spotFeedServerSnapshotIsFresh(
          _spotFeedServerReceivedAt[source],
          DateTime.now(),
        )) {
      return;
    }
    final revision = _spotFeedRevisions[source] ?? 0;
    final snapshot = await trackedQueryGet(
      'spots manual refresh: $source',
      query,
      const GetOptions(source: Source.server),
    );
    if (!spotSyncIsCurrent(generation, scope)) return;
    // A newer server event/local write wins, but a partial cache event does not.
    if ((_spotFeedRevisions[source] ?? 0) == revision) {
      _applySpotFeedSnapshot(source, snapshot);
    }
  }

  await Future.wait([
    refreshSource('approved', approvedSpotsForCurrentUserQuery()),
    refreshSource(
      'my submissions',
      spotsCollection()
          .where('visibility', isEqualTo: 'public')
          .where('addedByUid', isEqualTo: currentUser.uid),
    ),
  ]);
}
