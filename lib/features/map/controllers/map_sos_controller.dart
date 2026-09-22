import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';
import 'package:ccs_app/features/community/chats/navigation/chat_navigation.dart'
    show openMessageToUserFromContext;
import 'package:ccs_app/core/firestore/collections.dart'
    show liveLocationsCollection, sosReportsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, uniqueNonEmptyStrings;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show
        distanceBetweenLatLngMeters,
        normalizedHeadingDegrees,
        safeLatLngFromPosition;
import 'package:ccs_app/core/theme/app_theme.dart'
    show blue, panelGlass, sosAlertColor;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show localizedFriendActionError;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show updateCurrentUserPresenceFields;
import 'package:ccs_app/features/map/models/sos_report.dart'
    show
        SosReportData,
        SosRequestDraft,
        sosDescriptionLooksLikeSpam,
        sosReasonLabels;
import 'package:ccs_app/features/notifications/data/friend_location_notifications.dart'
    show notifyFriendsLiveLocationStartedNow;
import 'package:ccs_app/shared/models/user_role.dart' show roleName;
import 'map_session.dart';
import 'map_config.dart';

/// Coordinates sos behavior using screen-owned state and lifecycle.
class MapSosController implements MapSosActions {
  final MapSession host;
  MapSosController(this.host);

  @override
  void startSosReportSync() {
    if (!host.isVisible) {
      return;
    }

    host.sosReportSubscription?.cancel();
    host.sosReportSubscription = sosReportsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .debugSnapshots('map: active SOS reports listener')
        .listen(
          (snapshot) {
            if (!host.mounted) {
              return;
            }

            final reports = snapshot.docs
                .map((doc) => SosReportData.fromFirestore(doc))
                .where((report) => report.isActive)
                .toList();

            host.updateMap(() {
              host.sosReports = reports;

              final selected = host.selectedSosReport;
              if (selected != null) {
                final stillVisible = reports.any(
                  (report) => report.id == selected.id,
                );
                if (!stillVisible) {
                  host.selectedSosReport = null;
                }
              }
            });
          },
          onError: (_) {
            // Firestore rules may still be closed while this feature is being set up.
          },
        );
  }

  @override
  Future<SosRequestDraft?> showSosDescriptionDialog() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    String selectedReason = 'battery';
    String description = '';
    String? validationError;

    return showDialog<SosRequestDraft>(
      context: viewContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: panelGlass,
              title: CcsText(
                trText('Need help'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      trText('Choose SOS reason'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: sosReasonLabels.entries.map((entry) {
                        final selected = selectedReason == entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setDialogState(() {
                                selectedReason = entry.key;
                                validationError = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: double.infinity,
                              constraints: const BoxConstraints(minHeight: 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? blue
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? blue : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    child: selected
                                        ? const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: CcsText(
                                      trText(entry.value),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: false,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 220,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (value) {
                        description = value;
                        if (validationError != null) {
                          setDialogState(() => validationError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: trText('What happened?'),
                        hintText: trText(
                          'Describe what happened and what help you need.',
                        ),
                        errorText: validationError == null
                            ? null
                            : trText(validationError!),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: CcsText(trText('Cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final cleanDescription = description.trim();
                    if (sosDescriptionLooksLikeSpam(cleanDescription)) {
                      setDialogState(() {
                        validationError =
                            'Description looks like spam. Please write clearly what happened.';
                      });
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      SosRequestDraft(
                        reason: selectedReason,
                        description: cleanDescription,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: blue),
                  child: CcsText(
                    trText('Create SOS'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Future<List<String>> loadSosVisibleUserIds(String fallbackUid) async {
    try {
      final snapshot = await usersCollection()
          .limit(500)
          .debugGet(null, 'SOS: visible users query');
      final ids = snapshot.docs
          .map((doc) => stringFromFirebase(doc.data()['uid'], doc.id))
          .where((uid) => uid.trim().isNotEmpty)
          .toList();
      return uniqueNonEmptyStrings([fallbackUid, ...ids]);
    } catch (_) {
      return uniqueNonEmptyStrings([fallbackUid]);
    }
  }

  @override
  Future<void> startSosLiveLocationSharing(Position position) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final now = DateTime.now();
    const shareDuration = Duration(hours: 12);
    final expiresAt = now.add(shareDuration);
    final promptAt = expiresAt;
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = host.navigation.headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );
    final visibleToUserIds = await loadSosVisibleUserIds(firebaseUser.uid);

    host.liveLocationShareDuration = shareDuration;
    host.liveLocationPromptAt = promptAt;
    host.liveLocationExpiresAt = expiresAt;

    await liveLocationsCollection().doc(firebaseUser.uid).debugSet({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'name': currentUser.name,
      'photoUrl': currentUser.photoUrl,
      'role': roleName(currentUser.role),
      'verified': currentUser.verified,
      'heading': normalizedHeadingDegrees(
        heading,
        fallback: host.currentUserHeadingDegrees,
      ),
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'visibleToUserIds': visibleToUserIds,
      'visibleToChatId': '',
      'visibleToChatName': '',
      'shareScope': 'sos',
      'shareDurationMinutes': shareDuration.inMinutes,
      'promptAt': Timestamp.fromDate(promptAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await updateCurrentUserPresenceFields({
        'isSharingLiveLocation': true,
        'liveLocationExpiresAt': Timestamp.fromDate(expiresAt),
        'liveLocationVisibleToUserIds': visibleToUserIds,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'isOnline': true,
      }, label: 'presence: current user SOS live location started');
    } catch (error, stack) {
      debugPrint('SOS user live-location flag update failed: $error');
      debugPrint('$stack');
    }

    await notifyFriendsLiveLocationStartedNow(coordinates: location);

    if (!host.mounted) {
      return;
    }

    host.updateMap(() {
      host.currentUserLocation = location;
      host.displayedUserLocation = location;
      host.lastGpsUserLocation = location;
      host.lastUploadedLiveLocation = location;
      host.lastGpsUserLocationAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = speed;
      host.isSharingLiveLocation = true;
    });

    host.sharing.scheduleLiveLocationTimers();
    host.navigation.startNavigationTracking();
    host.navigation.updateFollowCamera(location, heading);

    final prompt = host.liveLocationPromptAt;
    final expiry = host.liveLocationExpiresAt;
    if (prompt != null && expiry != null) {
      unawaited(
        host.sharing.startNativeLiveLocationBackgroundService(
          uid: firebaseUser.uid,
          visibleToUserIds: visibleToUserIds,
          shareScope: 'sos',
          promptAt: prompt,
          expiresAt: expiry,
        ),
      );
    }

    host.liveLocationUploadTimer?.cancel();
    host.liveLocationUploadTimer = null;
    host.sharing.ensureLiveLocationUploadLoop();
  }

  @override
  Future<void> addSosReportAtCurrentLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isAddingSosReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before sharing your location.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final activeOwnSos = host.sosReports.any(
      (report) => report.uid == firebaseUser.uid && report.isActive,
    );
    if (activeOwnSos) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            trText('Only one active SOS is allowed.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    try {
      final existingOwnSos = await sosReportsCollection()
          .where('uid', isEqualTo: firebaseUser.uid)
          .where('status', isEqualTo: 'active')
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .limit(1)
          .debugGet(null, 'SOS: existing own active report query');
      if (existingOwnSos.docs.isNotEmpty) {
        if ((host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: panelGlass,
              content: CcsText(
                trText('Close your current SOS before creating a new one.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }
    } catch (_) {
      // Local check above still protects beta builds while rules/indexes are being updated.
    }

    final draft = await showSosDescriptionDialog();
    if (draft == null || draft.description.isEmpty) {
      return;
    }

    host.updateMap(() => host.isAddingSosReport = true);

    final position = await host.navigation.getMapUserPosition(showErrors: true);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      host.updateMap(() => host.isAddingSosReport = false);
      return;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 12));
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final docRef = sosReportsCollection().doc(firebaseUser.uid);

    try {
      await docRef.debugSet({
        'uid': firebaseUser.uid,
        'username': currentUser.username,
        'description': draft.description,
        'reason': draft.reason,
        'lat': position.latitude,
        'lng': position.longitude,
        'coordinates': GeoPoint(position.latitude, position.longitude),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAt': FieldValue.serverTimestamp(),
        'confirmationRequestedAt': null,
        'status': 'active',
      });
    } on FirebaseException catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        host.updateMap(() => host.isAddingSosReport = false);
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              error.code == 'permission-denied'
                  ? trText(
                      'Close the current SOS or wait one minute before creating another one.',
                    )
                  : 'Could not create SOS: ${error.message ?? error.code}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      return;
    }

    try {
      await startSosLiveLocationSharing(position);
    } catch (error, stack) {
      debugPrint('SOS live location start failed: $error');
      debugPrint('$stack');
    }

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    final newReport = SosReportData(
      id: docRef.id,
      uid: firebaseUser.uid,
      username: currentUser.username,
      description: draft.description,
      reason: draft.reason,
      coordinates: location,
      createdAtMillis: now.millisecondsSinceEpoch,
      expiresAtMillis: expiresAt.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
    );

    host.updateMap(() {
      host.currentUserLocation = location;
      host.selectedSpot = null;
      host.selectedPoliceReport = null;
      host.selectedSosReport = newReport;
      host.selectedLiveLocation = null;
      host.isAddingSosReport = false;
    });

    host.navigation.moveMapCamera(location, 15.5);

    ScaffoldMessenger.of(viewContext).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: CcsText(
          trText('SOS added on the map.'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Future<void> removeSosReport(SosReportData report) async {
    await sosReportsCollection().doc(report.id).debugSet({
      'status': 'removed',
      'removedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!host.mounted) {
      return;
    }

    host.updateMap(() {
      host.selectedSosReport = null;
      host.sosReports = host.sosReports
          .where((item) => item.id != report.id)
          .toList();
    });
  }

  @override
  Future<void> checkOwnSosDistance() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!(host.mounted && viewContext.mounted) ||
        host.sosConfirmationDialogOpen) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return;
    }

    SosReportData? ownSos;
    for (final report in host.sosReports) {
      if (report.uid == firebaseUser.uid && report.isActive) {
        ownSos = report;
        break;
      }
    }

    if (ownSos == null) {
      return;
    }

    final position = await host.navigation.getMapUserPosition(
      showErrors: false,
    );
    if (!(host.mounted && viewContext.mounted) || position == null) {
      return;
    }

    final freshLocation = safeLatLngFromPosition(position);
    if (freshLocation == null) {
      return;
    }
    final distance = distanceBetweenLatLngMeters(
      freshLocation,
      ownSos.coordinates,
    );

    host.updateMap(() => host.currentUserLocation = freshLocation);

    if (distance <= mapSosAutoCheckRadiusMeters) {
      return;
    }

    final requestedAt = ownSos.confirmationRequestedAtMillis;
    final now = DateTime.now();
    if (requestedAt > 0) {
      final requestedAtDate = DateTime.fromMillisecondsSinceEpoch(requestedAt);
      if (now.difference(requestedAtDate) >= mapSosNoAnswerAutoRemoveDelay) {
        await removeSosReport(ownSos);
      }
      return;
    }

    await sosReportsCollection().doc(ownSos.id).debugSet({
      'confirmationRequestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    host.sosConfirmationDialogOpen = true;
    final keep = await showDialog<bool>(
      context: viewContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: const CcsText(
            'Still need help?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: const CcsText(
            'You moved away from your SOS point. Do you still need help there?',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: CcsText(trText('No, remove')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: sosAlertColor),
              child: const CcsText(
                'Yes, still need',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    ).timeout(mapSosNoAnswerAutoRemoveDelay, onTimeout: () => false);

    host.sosConfirmationDialogOpen = false;

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (keep == true) {
      await sosReportsCollection().doc(ownSos.id).debugSet({
        'confirmationRequestedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await removeSosReport(ownSos);
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            trText('SOS removed from the map.'),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  Future<void> openSosMessage(SosReportData report) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    try {
      final snapshot = await usersCollection().doc(report.uid).debugGet();
      if (!snapshot.exists) {
        throw Exception('User profile is not available anymore.');
      }

      final user = FriendUserData.fromFirestore(snapshot);
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      await openMessageToUserFromContext(viewContext, user);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            localizedFriendActionError(error, 'Could not open chat.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }
}
