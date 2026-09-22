import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/events/models/event_forum_description.dart';
import 'package:ccs_app/core/firestore/query_pages.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugCollectionReferenceExtension,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show
        communityCountrySelection,
        currentUser,
        currentUserHomeCountryCode,
        firebaseReady;
import 'package:ccs_app/features/community/data/community_country.dart'
    show chooseProfileCountryMessage;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show forumCategoryById, forumCategoryIdFromFirebase;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show groupSpotIds, memberSpotGroups;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show
        currentUserCanModerateCommunityData,
        currentUserCanModerateCountry,
        userDataHasCommunityModerationAccess;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show notifyStaffAboutCommunityEvent;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show
        currentSpotSyncScope,
        firebaseSpotCacheBySource,
        spotSourcesWithServerSnapshot,
        spotSyncGeneration,
        spotSyncIsCurrent;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart'
    show SpotStatus, spotStatusName;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, roleFromFirebase, roleName, userRoleIsStaff;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
_legacyLatvianForumTopicsSnapshotFuture;

const maxForumTopicPhotos = 4;

List<String> forumTopicPhotos(Map<String, dynamic> data) =>
    stringListFromFirebase(data['photoUrls'], const [])
        .where((url) => Uri.tryParse(url)?.scheme == 'https')
        .take(maxForumTopicPhotos)
        .toList();

Future<String> createForumTopic({
  required String title,
  required String category,
  required String description,
  required String avatarUrl,
  List<String> photoUrls = const [],
}) async {
  if (photoUrls.length > maxForumTopicPhotos) {
    throw ArgumentError("Maximum 4 photos per topic.");
  }
  try {
    if (currentUserHomeCountryCode().isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'profile-country-required',
        message: chooseProfileCountryMessage,
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('Creating topic: $title');
    debugPrint('User: ${user?.uid}');
    debugPrint('Category: $category');

    if (user == null) {
      debugPrint('ERROR: user is null');
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-logged-in',
        message: 'Log in before creating a forum topic.',
      );
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .debugGet(null, 'forum: create topic user lookup');

    final userData = userDoc.data();
    final username =
        stringFromFirebase(userData?['username'], '').trim().isNotEmpty
        ? stringFromFirebase(userData?['username'], '')
        : stringFromFirebase(
            userData?['displayName'],
            currentUser.username.trim().isEmpty
                ? 'ccs_driver'
                : currentUser.username,
          );

    final categoryId = forumCategoryIdFromFirebase(category);
    final categoryTitle = forumCategoryById(categoryId).titleKey;
    final creatorRole = roleFromFirebase(userData?['role']);
    final creatorGlobalModerator = userDataHasCommunityModerationAccess(
      userData,
    );
    final isStaffCreator =
        userRoleIsStaff(creatorRole) ||
        (currentUser.uid == user.uid && userRoleIsStaff(currentUser.role));
    final topicStatus =
        isStaffCreator &&
            currentUserCanModerateCountry(
              communityCountrySelection.value,
              community: true,
            )
        ? 'approved'
        : 'pending';

    final docRef = await FirebaseFirestore.instance
        .collection('forum_topics')
        .debugAdd({
          'visibility': 'public',
          'title': title,
          'countryCode': communityCountrySelection.value,
          'authorCountryCode': currentUserHomeCountryCode(),
          'country': currentUser.country.trim(),
          'category': categoryTitle,
          'description': description,
          'avatarUrl': avatarUrl,
          'photoUrls': photoUrls,
          'categoryId': categoryId,
          'authorId': user.uid,
          'authorName': username,
          'authorRole': roleName(creatorRole),
          'authorVerified':
              userRoleIsStaff(creatorRole) || userData?['verified'] == true,
          'authorGlobalChatModerator': creatorGlobalModerator,
          'authorGlobalModerator': creatorGlobalModerator,
          'repliesCount': 0,
          'isPinned': false,
          'status': topicStatus,
          'rejectionReason': null,
          'reviewedBy': topicStatus == 'approved' ? user.uid : null,
          'reviewedAt': topicStatus == 'approved'
              ? FieldValue.serverTimestamp()
              : null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastReplyAt': FieldValue.serverTimestamp(),
        });

    if (topicStatus == 'pending') {
      await notifyStaffAboutCommunityEvent(
        type: 'forum_topic_pending',
        notificationId: 'forum_topic_pending_${docRef.id}',
        title: 'Forum topic waiting for review',
        body: '$title was submitted by @$username.',
        extra: {
          'topicId': docRef.id,
          'topicTitle': title,
          'categoryId': categoryId,
          'countryCode': communityCountrySelection.value,
        },
        resolveRecipientsOnServer: true,
      );
    }

    if (topicStatus == 'approved') {
      await sendPushNotificationEvent({
        'type': 'forum_topic_created',
        'topicId': docRef.id,
      });
    }

    debugPrint('SUCCESS: Topic $topicStatus: ${docRef.id}');
    forumTopicsRefreshTick.value++;
    return topicStatus;
  } catch (error, stack) {
    debugPrint('ERROR creating forum topic: $error');
    debugPrint('$stack');
    rethrow;
  }
}

String temporarySpotForumTopicId(String spotId) {
  return 'temporary_spot_$spotId';
}

bool groupForumAccessible(Map<String, dynamic> data) =>
    data['visibility'] != 'group' ||
    currentUserCanModerateCommunityData(data) ||
    memberSpotGroups.value.any(
      (group) => stringListFromFirebase(
        data['sharedGroupIds'],
        const [],
      ).contains(group.id),
    );

bool forumTopicIsVisibleNow(Map<String, dynamic> data) {
  if (!groupForumAccessible(data)) return false;
  final status = stringFromFirebase(data['status'], 'approved');
  if (status != 'approved') {
    return false;
  }

  final autoExpiresAtMillis = timestampMillisFromFirebase(
    data['autoExpiresAt'] ?? data['temporarySpotExpiresAt'],
  );
  if (autoExpiresAtMillis <= 0) {
    return true;
  }

  return autoExpiresAtMillis > DateTime.now().millisecondsSinceEpoch;
}

String temporarySpotForumDescription(CarSpot spot) {
  final parts = <String>[];
  if (spot.cityCountry.trim().isNotEmpty) {
    parts.add('${trText('Location')}: ${spot.cityCountry.trim()}');
  }
  if (spot.startsAtMillis != null) {
    parts.add(
      '${trText('Starts at')}: ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!))}',
    );
  }
  if (spot.expiresAtMillis != null) {
    parts.add(
      '${trText('Ends at')}: ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(spot.expiresAtMillis!))}',
    );
  }

  return eventForumDescription(spot.description, parts);
}

Map<String, Object?> temporarySpotForumTopicData({
  required CarSpot spot,
  required String authorId,
  required String authorName,
  required String authorCountry,
  required String authorCountryCode,
  required UserRole authorRole,
  required bool authorVerified,
  required bool authorGlobalModerator,
  required String status,
  required Object? reviewedBy,
  required Object? reviewedAt,
  bool includeCreateTimestamps = true,
}) {
  final startsAt = spot.startsAtMillis == null
      ? null
      : Timestamp.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
  final expiresAt = spot.expiresAtMillis == null
      ? null
      : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);

  return {
    'visibility': spot.visibility,
    'sharedGroupIds': spot.sharedGroupIds,
    'sharedGroups': spot.sharedGroups,
    'title': spot.name.trim().isEmpty ? 'Event' : spot.name,
    'countryCode': spot.effectiveCountryCode,
    'authorCountryCode': authorCountryCode,
    'country': authorCountry,
    'category': forumCategoryById('meets_events').titleKey,
    'description': temporarySpotForumDescription(spot),
    'avatarUrl': spot.photoUrl,
    'categoryId': 'meets_events',
    'authorId': authorId,
    'authorName': authorName,
    'authorRole': roleName(authorRole),
    'authorVerified': authorVerified,
    'authorGlobalChatModerator': authorGlobalModerator,
    'authorGlobalModerator': authorGlobalModerator,
    'repliesCount': 0,
    'isPinned': false,
    'status': status,
    'rejectionReason': null,
    'reviewedBy': reviewedBy,
    'reviewedAt': reviewedAt,
    if (includeCreateTimestamps) 'createdAt': FieldValue.serverTimestamp(),
    if (includeCreateTimestamps) 'lastReplyAt': FieldValue.serverTimestamp(),
    'source': 'temporary_spot',
    'isSpotTopic': true,
    'spotId': spot.id,
    'temporarySpotId': spot.id,
    'temporarySpotStartsAt': startsAt,
    'temporarySpotExpiresAt': expiresAt,
    'autoExpiresAt': expiresAt,
  };
}

Future<void> createTemporarySpotForumTopic(CarSpot spot) async {
  await ensureTemporarySpotForumTopic(spot, backfillFromExistingSpot: false);
}

Future<bool> ensureTemporarySpotForumTopic(
  CarSpot spot, {
  required bool backfillFromExistingSpot,
}) async {
  if (!spot.isTemporary || spot.id.trim().isEmpty) {
    return false;
  }

  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    return false;
  }

  final expiresAtMillis = spot.expiresAtMillis;
  if (backfillFromExistingSpot &&
      expiresAtMillis != null &&
      expiresAtMillis <= DateTime.now().millisecondsSinceEpoch) {
    return false;
  }

  try {
    final topicRef = FirebaseFirestore.instance
        .collection('forum_topics')
        .doc(temporarySpotForumTopicId(spot.id));
    final existingTopic = await topicRef.debugGet(
      null,
      backfillFromExistingSpot
          ? 'forum: temporary spot topic backfill existing check'
          : 'forum: temporary spot topic create existing check',
    );
    if (existingTopic.exists) {
      return true;
    }

    final authorUid =
        backfillFromExistingSpot && spot.addedByUid.trim().isNotEmpty
        ? spot.addedByUid.trim()
        : firebaseUser.uid;
    Map<String, dynamic>? userData;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authorUid)
          .debugGet(null, 'forum: temporary spot author lookup');
      userData = userDoc.data();
    } catch (_) {
      userData = null;
    }

    final creatorRole = roleFromFirebase(userData?['role']);
    final authorCountry = stringFromFirebase(
      userData?['country'],
      authorUid == currentUser.uid ? currentUser.country : '',
    ).trim();
    final authorCountryCode =
        countryIsoCode(authorCountry) ?? spot.effectiveCountryCode;
    final creatorGlobalModerator = userDataHasCommunityModerationAccess(
      userData,
    );
    // Keep this equal to the spot's stored creator name. Firestore rules
    // validate auto-created temporary spot topics against the source spot, so
    // using the current profile username here can block backfills if the user
    // renamed their account after creating the spot.
    final authorName = spot.addedBy.trim().isNotEmpty
        ? spot.addedBy.trim()
        : stringFromFirebase(
            userData?['username'],
            currentUser.username.trim().isEmpty
                ? 'ccs_driver'
                : currentUser.username,
          );
    final topicStatus = spot.status == SpotStatus.approved
        ? 'approved'
        : 'pending';

    await topicRef.debugSet(
      temporarySpotForumTopicData(
        spot: spot,
        authorId: authorUid,
        authorName: authorName,
        authorCountry: authorCountry,
        authorCountryCode: authorCountryCode,
        authorRole: creatorRole,
        authorVerified:
            userRoleIsStaff(creatorRole) || userData?['verified'] == true,
        authorGlobalModerator: creatorGlobalModerator,
        status: topicStatus,
        reviewedBy: topicStatus == 'approved' ? firebaseUser.uid : null,
        reviewedAt: topicStatus == 'approved'
            ? FieldValue.serverTimestamp()
            : null,
      ),
      null,
      backfillFromExistingSpot
          ? 'forum: auto temporary spot topic backfill create'
          : 'forum: auto temporary spot topic create',
    );
    forumTopicsRefreshTick.value++;

    if (topicStatus == 'approved' &&
        !backfillFromExistingSpot &&
        !spot.isGroupSpot) {
      await sendPushNotificationEvent({
        'type': 'forum_topic_created',
        'topicId': topicRef.id,
      });
    }

    if (topicStatus == 'pending') {
      await notifyStaffAboutCommunityEvent(
        type: 'forum_topic_pending',
        notificationId: 'forum_topic_pending_${topicRef.id}',
        title: 'Forum topic waiting for review',
        body: '${spot.name} was submitted by @$authorName.',
        extra: {
          'topicId': topicRef.id,
          'topicTitle': spot.name,
          'categoryId': 'meets_events',
          'spotId': spot.id,
        },
        resolveRecipientsOnServer: true,
      );
    }
    return true;
  } catch (error, stack) {
    debugPrint('Could not create temporary spot forum topic: $error');
    debugPrint('$stack');
    return false;
  }
}

bool temporarySpotNeedsForumTopicBackfill(CarSpot spot) {
  if (!spot.isTemporary || spot.id.trim().isEmpty) {
    return false;
  }
  if (spot.status != SpotStatus.approved && spot.status != SpotStatus.pending) {
    return false;
  }
  final expiresAtMillis = spot.expiresAtMillis;
  if (expiresAtMillis == null) {
    return false;
  }
  return expiresAtMillis > DateTime.now().millisecondsSinceEpoch;
}

Future<void>? _activeTemporarySpotForumTopicSync;

final Set<String> _checkedTemporarySpotForumTopics = {};

final Map<String, DateTime> _temporarySpotForumTopicAttempts = {};

Future<void> syncActiveTemporarySpotForumTopics() {
  if (!firebaseReady || FirebaseAuth.instance.currentUser == null) {
    return Future<void>.value();
  }

  if (!spotSourcesWithServerSnapshot.containsAll([
    'approved',
    'my submissions',
  ])) {
    return Future<void>.value();
  }
  final existing = _activeTemporarySpotForumTopicSync;
  if (existing != null) {
    return existing;
  }

  final sync = _syncActiveTemporarySpotForumTopicsOnce();
  _activeTemporarySpotForumTopicSync = sync;
  return sync.whenComplete(() {
    if (identical(_activeTemporarySpotForumTopicSync, sync)) {
      _activeTemporarySpotForumTopicSync = null;
    }
  });
}

Future<void> _syncActiveTemporarySpotForumTopicsOnce() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final generation = spotSyncGeneration;
  final scope = currentSpotSyncScope;
  // Recheck the cache after each await so spots arriving during the backfill
  // are included, without repeatedly checking successful or failed topics.
  while (uid != null &&
      FirebaseAuth.instance.currentUser?.uid == uid &&
      spotSyncIsCurrent(generation, scope)) {
    final candidates = <String, CarSpot>{
      for (final source in ['approved', 'my submissions'])
        for (final spot
            in firebaseSpotCacheBySource[source]?.values ?? <CarSpot>[])
          if (!spot.isGroupSpot && temporarySpotNeedsForumTopicBackfill(spot))
            spot.id: spot,
    };
    CarSpot? next;
    final now = DateTime.now();
    for (final spot in candidates.values) {
      final key = '$uid/${spot.id}';
      final lastAttempt = _temporarySpotForumTopicAttempts[key];
      if (!_checkedTemporarySpotForumTopics.contains(key) &&
          (lastAttempt == null ||
              now.difference(lastAttempt) >= const Duration(minutes: 5))) {
        next = spot;
        break;
      }
    }
    if (next == null) return;
    final key = '$uid/${next.id}';
    _temporarySpotForumTopicAttempts[key] = now;
    if (await ensureTemporarySpotForumTopic(
      next,
      backfillFromExistingSpot: true,
    )) {
      _checkedTemporarySpotForumTopics.add(key);
    }
  }
}

Future<void> updateTemporarySpotForumTopicAfterSpotReview(
  CarSpot spot,
  SpotStatus status, {
  String rejectionReason = '',
}) async {
  if (spot.isGroupSpot) return;
  if (!spot.isTemporary || spot.id.trim().isEmpty) {
    return;
  }

  try {
    final topicRef = FirebaseFirestore.instance
        .collection('forum_topics')
        .doc(temporarySpotForumTopicId(spot.id));
    final snapshot = await topicRef.debugGet(
      null,
      'forum: auto temporary spot topic review get',
    );
    if (!snapshot.exists) {
      return;
    }

    await topicRef.debugUpdate({
      'status': spotStatusName(status),
      'rejectionReason': status == SpotStatus.rejected
          ? rejectionReason.trim()
          : null,
      'reviewedBy': currentUser.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'temporarySpotStartsAt': spot.startsAtMillis == null
          ? null
          : Timestamp.fromMillisecondsSinceEpoch(spot.startsAtMillis!),
      'temporarySpotExpiresAt': spot.expiresAtMillis == null
          ? null
          : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!),
      'autoExpiresAt': spot.expiresAtMillis == null
          ? null
          : Timestamp.fromMillisecondsSinceEpoch(spot.expiresAtMillis!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, 'forum: auto temporary spot topic review update');
    forumTopicsRefreshTick.value++;
  } catch (error, stack) {
    debugPrint('Could not update temporary spot forum topic: $error');
    debugPrint('$stack');
  }
}

Future<List<DocumentSnapshot<Map<String, dynamic>>>>
loadRegionalForumTopicDocuments(
  CollectionReference<Map<String, dynamic>> collection,
  String debugLabel,
) async {
  final selectedCode = communityCountrySelection.value;
  // Page by document ID so legacy records without timestamps are included.
  // The callers sort the complete result by pin/activity and filter categories.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> readPages(
    Query<Map<String, dynamic>> query,
    String label,
  ) => collectQueryPages<QueryDocumentSnapshot<Map<String, dynamic>>>(
    pageSize: 120,
    readPage: (cursor, size) async {
      var page = query.orderBy(FieldPath.documentId).limit(size);
      if (cursor != null) page = page.startAfterDocument(cursor);
      return (await page.debugGet(null, label)).docs;
    },
  );
  final regional = await readPages(
    collection
        .where('visibility', isEqualTo: 'public')
        .where('countryCode', isEqualTo: selectedCode),
    '$debugLabel: regional',
  );
  final byId = <String, DocumentSnapshot<Map<String, dynamic>>>{
    for (final doc in regional) doc.id: doc,
  };
  if (selectedCode == 'LV') {
    final legacyRequest = _legacyLatvianForumTopicsSnapshotFuture ??= readPages(
      collection.where('visibility', isEqualTo: 'public'),
      'forum: legacy Latvian topics session cache',
    );
    try {
      for (final doc in await legacyRequest) {
        if (!doc.data().containsKey('countryCode')) byId[doc.id] = doc;
      }
    } catch (_) {
      if (identical(_legacyLatvianForumTopicsSnapshotFuture, legacyRequest)) {
        _legacyLatvianForumTopicsSnapshotFuture = null;
      }
      rethrow;
    }
  }
  final groupIds = groupSpotIds.values.expand((ids) => ids).toSet();
  for (final id in groupIds) {
    try {
      final doc = await collection
          .doc(temporarySpotForumTopicId(id))
          .get(const GetOptions(source: Source.server));
      if (doc.exists && groupForumAccessible(doc.data()!)) {
        byId[doc.id] = doc;
      }
    } catch (_) {
      /* Membership may have changed during the load. */
    }
  }
  return byId.values.toList(growable: false);
}
