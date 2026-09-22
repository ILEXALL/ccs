import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/map/models/spot_presence_grouping.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/friends/data/friends_repository.dart'
    show loadCurrentFriendUids;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show
        friendUserCarIconAsset,
        liveLocationSpotStaleKeepRadiusMeters,
        publicLiveLocationAudienceMarker,
        regularUserCarIconAsset,
        verifiedUserCarIconAsset;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/widgets/spot_presence_sheet.dart'
    show SpotPeopleSheet;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'map_session.dart';

/// Coordinates presence behavior using screen-owned state and lifecycle.
class MapPresenceController implements MapPresenceActions {
  final MapSession host;
  MapPresenceController(this.host);

  @override
  Future<void> loadFriendLiveLocationUids() async {
    if (!host.isVisible) {
      return;
    }

    try {
      final friendUids = await loadCurrentFriendUids();

      if (!host.mounted) {
        return;
      }

      host.updateMap(() => host.friendLiveLocationUids = friendUids.toSet());
    } catch (_) {
      // Friend icon highlighting is best-effort.
    }
  }

  @override
  bool liveLocationIsFriend(LiveLocationData location) {
    return host.friendLiveLocationUids.contains(location.uid);
  }

  @override
  Map<String, List<String>> get spotPresenceGroups => groupSpotPresence(
    {
      for (final spot in host.layers.visibleSpots.where(
        (spot) =>
            spot.isVisibleOnMapNow &&
            (!spot.isTemporary || spot.isTemporaryActiveNow),
      ))
        spot.id: spot.coordinates,
    },
    host.liveLocations.map(
      (p) => PresencePoint(
        p.uid,
        p.coordinates,
        p.updatedAtMillis,
        p.expiresAtMillis,
      ),
    ),
    DateTime.now().millisecondsSinceEpoch,
  );

  @override
  List<LiveLocationData> peopleAtSpot(CarSpot spot) {
    final ids = spotPresenceGroups[spot.id]?.toSet() ?? <String>{};
    return host.liveLocations
        .where((person) => ids.contains(person.uid))
        .toList();
  }

  @override
  void showSpotPeople(CarSpot spot) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    showModalBottomSheet<void>(
      context: viewContext,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10141C),
      builder: (_) => SpotPeopleSheet(
        title: spot.name,
        load: () => (host.mounted && viewContext.mounted)
            ? peopleAtSpot(spot)
            : <LiveLocationData>[],
        onProfile: (person) {
          Navigator.of(viewContext).pop();
          openUserProfile(
            viewContext,
            uid: person.uid,
            fallbackUsername: person.username,
          );
        },
      ),
    );
  }

  @override
  String liveLocationCarIconAsset(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return friendUserCarIconAsset;
    }

    if (location.verified) {
      return verifiedUserCarIconAsset;
    }

    return regularUserCarIconAsset;
  }

  @override
  String liveLocationTooltipMessage(LiveLocationData location) {
    if (liveLocationIsFriend(location)) {
      return '${displayUsername(location.username)} is your friend and is sharing live location';
    }

    if (location.verified) {
      return '${displayUsername(location.username)} is verified and is sharing live location';
    }

    return '${displayUsername(location.username)} is sharing live location';
  }

  @override
  bool liveLocationCanBeSeenByCurrentUser(
    LiveLocationData location,
    User? firebaseUser,
  ) {
    if (firebaseUser == null) {
      return false;
    }

    if (location.uid == firebaseUser.uid) {
      return true;
    }

    if (location.shareScope.trim().toLowerCase() == 'public' ||
        location.visibleToUserIds.contains(publicLiveLocationAudienceMarker)) {
      return true;
    }

    return location.visibleToUserIds.contains(firebaseUser.uid);
  }

  @override
  bool liveLocationIsNearAnyApprovedSpot(LiveLocationData location) {
    for (final spot in approvedPublicSpots()) {
      if (!spot.isVisibleOnMapNow) {
        continue;
      }

      final distanceMeters = distanceBetweenLatLngMeters(
        location.coordinates,
        spot.coordinates,
      );
      if (distanceMeters <= liveLocationSpotStaleKeepRadiusMeters) {
        return true;
      }
    }

    return false;
  }

  @override
  bool liveLocationShouldStayVisibleOnMap(LiveLocationData location) {
    if (location.isExpired) {
      return false;
    }

    if (!location.isStale) {
      return true;
    }

    return liveLocationIsNearAnyApprovedSpot(location);
  }

  @override
  void updateLiveLocationCacheFromSnapshot(
    Map<String, LiveLocationData> cache,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.removed) {
        cache.remove(change.doc.id);
        continue;
      }

      final location = LiveLocationData.fromFirestore(change.doc);
      if (!liveLocationShouldStayVisibleOnMap(location)) {
        cache.remove(location.uid);
      } else {
        cache[location.uid] = location;
      }
    }
  }

  @override
  void removeLiveLocationFromCaches(String uid) {
    host.visibleLiveLocationsByUid.remove(uid);
    host.publicLiveLocationsByUid.remove(uid);
  }

  @override
  void publishLiveLocationCaches() {
    if (!host.mounted) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      host.updateMap(() {
        host.liveLocations = const [];
        host.selectedLiveLocation = null;
        host.isSharingLiveLocation = false;
        host.liveLocationPromptAt = null;
        host.liveLocationExpiresAt = null;
      });
      host.sharing.cancelLiveLocationTimers(keepUploadTimer: false);
      return;
    }

    final mergedByUid = <String, LiveLocationData>{};
    for (final location in host.publicLiveLocationsByUid.values) {
      if (liveLocationShouldStayVisibleOnMap(location) &&
          liveLocationCanBeSeenByCurrentUser(location, firebaseUser)) {
        mergedByUid[location.uid] = location;
      }
    }

    for (final location in host.visibleLiveLocationsByUid.values) {
      if (liveLocationShouldStayVisibleOnMap(location) &&
          liveLocationCanBeSeenByCurrentUser(location, firebaseUser)) {
        mergedByUid[location.uid] = location;
      }
    }

    final visibleLocations = mergedByUid.values.toList()
      ..sort((first, second) {
        return second.updatedAtMillis.compareTo(first.updatedAtMillis);
      });

    LiveLocationData? ownLocation;
    LiveLocationData? nextSelectedLiveLocation;
    final selectedUid = host.selectedLiveLocation?.uid;

    for (final location in visibleLocations) {
      if (location.uid == firebaseUser.uid) {
        ownLocation = location;
      }

      if (selectedUid != null &&
          location.uid == selectedUid &&
          location.uid != firebaseUser.uid) {
        nextSelectedLiveLocation = location;
      }
    }

    var shouldScheduleTimers = false;
    var shouldCancelTimers = false;

    host.updateMap(() {
      host.liveLocations = visibleLocations;
      host.selectedLiveLocation = selectedUid == null
          ? null
          : nextSelectedLiveLocation;

      if (ownLocation != null) {
        host.isSharingLiveLocation = true;
        host.liveLocationPromptAt = DateTime.fromMillisecondsSinceEpoch(
          ownLocation.promptAtMillis,
        );
        host.liveLocationExpiresAt = DateTime.fromMillisecondsSinceEpoch(
          ownLocation.expiresAtMillis,
        );
        host.liveLocationShareDuration = Duration(
          minutes: ownLocation.shareDurationMinutes,
        );
        shouldScheduleTimers = true;
      } else if (!host.isTogglingLiveLocation) {
        host.isSharingLiveLocation = false;
        host.liveLocationPromptAt = null;
        host.liveLocationExpiresAt = null;
        shouldCancelTimers = true;
      }
    });

    if (shouldScheduleTimers) {
      host.sharing.scheduleLiveLocationTimers();
    } else if (shouldCancelTimers) {
      host.sharing.cancelLiveLocationTimers(keepUploadTimer: false);
      host.nativeLiveLocationBackgroundSignature = null;
    }

    if (ownLocation != null) {
      host.sharing.ensureLiveLocationUploadLoop();
    }
  }

  @override
  void ensureLiveLocationStaleSweepTimer() {
    host.liveLocationStaleSweepTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => publishLiveLocationCaches(),
    );
  }

  @override
  void startLiveLocationSync() {
    if (!host.isVisible) {
      return;
    }

    host.liveLocationSubscription?.cancel();
    host.publicLiveLocationSubscription?.cancel();
    host.ownLiveLocationSubscription?.cancel();
    final currentFirebaseUser = FirebaseAuth.instance.currentUser;

    if (currentFirebaseUser == null) {
      host.visibleLiveLocationsByUid.clear();
      host.publicLiveLocationsByUid.clear();
      host.liveLocationStaleSweepTimer?.cancel();
      host.liveLocationStaleSweepTimer = null;
      host.updateMap(() {
        host.liveLocations = const [];
        host.selectedLiveLocation = null;
        host.isSharingLiveLocation = false;
        host.liveLocationPromptAt = null;
        host.liveLocationExpiresAt = null;
      });
      host.sharing.cancelLiveLocationTimers(keepUploadTimer: false);
      host.nativeLiveLocationBackgroundSignature = null;
      return;
    }

    host.visibleLiveLocationsByUid.clear();
    host.publicLiveLocationsByUid.clear();
    ensureLiveLocationStaleSweepTimer();

    host.ownLiveLocationSubscription = liveLocationsCollection()
        .doc(currentFirebaseUser.uid)
        .debugSnapshots('map: own live location document listener')
        .listen(
          (snapshot) {
            if (!host.mounted) {
              return;
            }

            if (!snapshot.exists) {
              removeLiveLocationFromCaches(currentFirebaseUser.uid);
              host.updateMap(() {
                host.liveLocations = host.liveLocations
                    .where(
                      (location) => location.uid != currentFirebaseUser.uid,
                    )
                    .toList();
                if (!host.isTogglingLiveLocation) {
                  host.isSharingLiveLocation = false;
                  host.liveLocationPromptAt = null;
                  host.liveLocationExpiresAt = null;
                }
              });
              publishLiveLocationCaches();
              return;
            }

            final ownLocation = LiveLocationData.fromFirestore(snapshot);
            if (!liveLocationShouldStayVisibleOnMap(ownLocation)) {
              removeLiveLocationFromCaches(ownLocation.uid);
              host.updateMap(() {
                host.liveLocations = host.liveLocations
                    .where((location) => location.uid != ownLocation.uid)
                    .toList();
                if (!host.isTogglingLiveLocation) {
                  host.isSharingLiveLocation = false;
                  host.liveLocationPromptAt = null;
                  host.liveLocationExpiresAt = null;
                }
              });
              publishLiveLocationCaches();
              return;
            }

            if (ownLocation.shareScope.trim().toLowerCase() == 'public' ||
                ownLocation.visibleToUserIds.contains(
                  publicLiveLocationAudienceMarker,
                )) {
              host.publicLiveLocationsByUid[ownLocation.uid] = ownLocation;
              host.visibleLiveLocationsByUid.remove(ownLocation.uid);
            } else {
              host.visibleLiveLocationsByUid[ownLocation.uid] = ownLocation;
              host.publicLiveLocationsByUid.remove(ownLocation.uid);
            }

            host.updateMap(() {
              host.currentUserLocation = ownLocation.coordinates;
              host.displayedUserLocation = ownLocation.coordinates;
              host.lastGpsUserLocation = ownLocation.coordinates;
              host.lastUploadedLiveLocation = ownLocation.coordinates;
              host.lastGpsUserLocationAt = DateTime.now();
              host.currentUserHeadingDegrees = ownLocation.headingDegrees;
              host.isSharingLiveLocation = true;
              host.liveLocationPromptAt = DateTime.fromMillisecondsSinceEpoch(
                ownLocation.promptAtMillis,
              );
              host.liveLocationExpiresAt = DateTime.fromMillisecondsSinceEpoch(
                ownLocation.expiresAtMillis,
              );
              host.liveLocationShareDuration = Duration(
                minutes: ownLocation.shareDurationMinutes,
              );
              host.liveLocations = [
                ...host.liveLocations.where(
                  (location) => location.uid != ownLocation.uid,
                ),
                ownLocation,
              ];
            });
            host.sharing.scheduleLiveLocationTimers();

            if (host.mapCenteredOnCurrentUser) {
              host.navigation.updateFollowCamera(
                ownLocation.coordinates,
                ownLocation.headingDegrees,
              );
            }

            publishLiveLocationCaches();
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );

    host.publicLiveLocationSubscription = liveLocationsCollection()
        .where(
          'visibleToUserIds',
          arrayContains: publicLiveLocationAudienceMarker,
        )
        .debugSnapshots('map: public live locations listener')
        .listen(
          (snapshot) {
            updateLiveLocationCacheFromSnapshot(
              host.publicLiveLocationsByUid,
              snapshot,
            );
            publishLiveLocationCaches();
          },
          onError: (_) {
            // Public live-location reads depend on Firestore rules being deployed.
          },
        );

    host.liveLocationSubscription = liveLocationsCollection()
        .where('visibleToUserIds', arrayContains: currentFirebaseUser.uid)
        .debugSnapshots('map: visible live locations listener')
        .listen(
          (snapshot) {
            updateLiveLocationCacheFromSnapshot(
              host.visibleLiveLocationsByUid,
              snapshot,
            );
            publishLiveLocationCaches();
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }
}
