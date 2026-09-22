import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show memberSpotGroups;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show groupSpotIds;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show firebaseSpotCacheBySource, spotSyncIsCurrent, spotSyncSubscriptions;
import 'package:ccs_app/features/spots/data/spot_feed_projection.dart'
    show publishFirebaseSpotCaches;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;

final Map<String, StreamSubscription> _groupSpotLinks = {};

final Map<String, StreamSubscription> _groupSpotDocuments = {};

Future<void> groupSpotCancellation = Future<void>.value();

void stopGroupSpotSync() {
  final pending = <Future<void>>[groupSpotCancellation];
  for (final subscription in [
    ..._groupSpotLinks.values,
    ..._groupSpotDocuments.values,
  ]) {
    pending.add(subscription.cancel());
  }
  _groupSpotLinks.clear();
  _groupSpotDocuments.clear();
  groupSpotIds.clear();
  memberSpotGroups.value = [];
  firebaseSpotCacheBySource.remove('group spots');
  groupSpotCancellation = Future.wait(pending).then((_) {});
}

void startGroupSpotSync(int generation, String scope) {
  final uid = currentUser.uid;
  final membership = FirebaseFirestore.instance
      .collection('chats')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .listen(
        (snapshot) {
          if (!spotSyncIsCurrent(generation, scope)) return;
          final groups = snapshot.docs
              .map(ChatThreadData.fromFirestore)
              .where((chat) => chat.isGroup)
              .toList();
          memberSpotGroups.value = groups;
          forumTopicsRefreshTick.value++;
          final ids = groups.map((group) => group.id).toSet();
          for (final removed
              in _groupSpotLinks.keys
                  .where((id) => !ids.contains(id))
                  .toList()) {
            unawaited(_groupSpotLinks.remove(removed)!.cancel());
            groupSpotIds.remove(removed);
          }
          void reconcile() {
            if (!spotSyncIsCurrent(generation, scope)) return;
            final wanted = groupSpotIds.values.expand((ids) => ids).toSet();
            final cache = firebaseSpotCacheBySource.putIfAbsent(
              'group spots',
              () => {},
            );
            for (final removed
                in _groupSpotDocuments.keys
                    .where((id) => !wanted.contains(id))
                    .toList()) {
              unawaited(_groupSpotDocuments.remove(removed)!.cancel());
              cache.remove(removed);
            }
            for (final id in wanted) {
              if (_groupSpotDocuments.containsKey(id)) continue;
              _groupSpotDocuments[id] = spotsCollection()
                  .doc(id)
                  .snapshots()
                  .listen(
                    (doc) {
                      if (!spotSyncIsCurrent(generation, scope)) return;
                      if (doc.exists) {
                        final spot = CarSpot.fromFirestore(doc);
                        if ((spot.status == SpotStatus.approved ||
                                spot.addedByUid == uid) &&
                            canViewGroupSpot(spot)) {
                          cache[id] = spot;
                        } else {
                          cache.remove(id);
                        }
                      } else {
                        cache.remove(id);
                      }
                      publishFirebaseSpotCaches();
                    },
                    onError: (Object error) {
                      cache.remove(id);
                      publishFirebaseSpotCaches();
                    },
                  );
            }
            cache.removeWhere((_, spot) => !canViewGroupSpot(spot));
            publishFirebaseSpotCaches();
          }

          for (final id in ids) {
            if (_groupSpotLinks.containsKey(id)) continue;
            _groupSpotLinks[id] = FirebaseFirestore.instance
                .collection('chats')
                .doc(id)
                .collection('spot_links')
                .snapshots()
                .listen(
                  (links) {
                    if (!spotSyncIsCurrent(generation, scope)) return;
                    groupSpotIds[id] = links.docs
                        .where(
                          (doc) =>
                              doc.data()['published'] == true ||
                              doc.data()['authorUid'] == uid,
                        )
                        .map((doc) => doc.id)
                        .toSet();
                    reconcile();
                    forumTopicsRefreshTick.value++;
                  },
                  onError: (Object error) {
                    groupSpotIds.remove(id);
                    reconcile();
                  },
                );
          }
          reconcile();
        },
        onError: (Object error) {
          if (!spotSyncIsCurrent(generation, scope)) return;
          stopGroupSpotSync();
          publishFirebaseSpotCaches();
        },
      );
  spotSyncSubscriptions.add(membership);
}
