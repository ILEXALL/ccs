import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show policeReportsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters, safeLatLngFromPosition;
import 'package:ccs_app/core/theme/app_theme.dart' show panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;
import 'map_session.dart';
import 'map_config.dart';

/// Coordinates police behavior using screen-owned state and lifecycle.
class MapPoliceController implements MapPoliceActions {
  final MapSession host;
  MapPoliceController(this.host);

  @override
  void startPoliceReportSync() {
    if (!host.isVisible) {
      return;
    }

    host.policeReportSubscription?.cancel();
    host.policeReportSubscription = policeReportsCollection()
        .where('expiresAt', isGreaterThan: Timestamp.now())
        .debugSnapshots('map: active police reports listener')
        .listen(
          (snapshot) {
            if (!host.mounted) {
              return;
            }

            final reports = snapshot.docs
                .map((doc) => PoliceReportData.fromFirestore(doc))
                .where((report) => report.isActive)
                .toList();

            host.updateMap(() {
              host.policeReports = reports;

              final selected = host.selectedPoliceReport;
              if (selected != null) {
                final stillVisible = reports.any(
                  (report) => report.id == selected.id,
                );
                if (!stillVisible) {
                  host.selectedPoliceReport = null;
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
  double? policeReportDistanceMeters(PoliceReportData report) {
    final location = host.currentUserLocation;

    if (location == null) {
      return null;
    }

    return const Distance().as(LengthUnit.Meter, location, report.coordinates);
  }

  @override
  bool isPoliceReportCreatorCooldownOver(PoliceReportData report) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      report.createdAtMillis,
    );

    return DateTime.now().difference(createdAt) >=
        mapPoliceReportCreatorVoteCooldown;
  }

  @override
  bool canVotePoliceReportFromCurrentMapLocation(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return false;
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null || distance > mapPoliceReportVoteRadiusMeters) {
      return false;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return false;
    }

    return true;
  }

  @override
  String policeReportVoteHint(PoliceReportData report) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return 'Log in to confirm this police mark.';
    }

    final distance = policeReportDistanceMeters(report);

    if (distance == null) {
      return 'Move to your current location before confirming this mark.';
    }

    if (distance > mapPoliceReportVoteRadiusMeters) {
      return 'Get closer to confirm this police mark.';
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      return 'You created this mark. You can confirm it later if you drive by this spot again.';
    }

    return '';
  }

  @override
  Future<void> addPoliceReportAtCurrentLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isAddingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before adding a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    host.updateMap(() => host.isAddingPoliceReport = true);

    final position = await host.navigation.getMapUserPosition(showErrors: true);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      host.updateMap(() => host.isAddingPoliceReport = false);
      return;
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 2));
    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }

    for (final report in host.layers.visiblePoliceReports) {
      final distance = distanceBetweenLatLngMeters(
        location,
        report.coordinates,
      );
      if (distance <= mapPoliceReportDuplicateRadiusMeters) {
        host.updateMap(() => host.isAddingPoliceReport = false);
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: panelGlass,
            content: CcsText(
              trText('In this area police is already marked.'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        host.updateMap(() {
          host.selectedSpot = null;
          host.selectedPoliceReport = report;
          host.selectedSosReport = null;
          host.selectedLiveLocation = null;
        });
        host.navigation.moveMapCamera(report.coordinates, 15.5);
        return;
      }
    }

    try {
      final activePoliceSnapshot = await policeReportsCollection()
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .where('status', isEqualTo: 'active')
          .debugGet(null, 'police: active nearby reports query');
      for (final doc in activePoliceSnapshot.docs) {
        final report = PoliceReportData.fromFirestore(doc);
        final distance = distanceBetweenLatLngMeters(
          location,
          report.coordinates,
        );
        if (distance <= mapPoliceReportDuplicateRadiusMeters) {
          if ((host.mounted && viewContext.mounted)) {
            host.updateMap(() => host.isAddingPoliceReport = false);
            ScaffoldMessenger.of(viewContext).showSnackBar(
              SnackBar(
                backgroundColor: panelGlass,
                content: CcsText(
                  trText('In this area police is already marked.'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            host.updateMap(() {
              host.selectedSpot = null;
              host.selectedPoliceReport = report;
              host.selectedSosReport = null;
              host.selectedLiveLocation = null;
            });
            host.navigation.moveMapCamera(report.coordinates, 15.5);
          }
          return;
        }
      }
    } catch (_) {
      // Local visible reports are already checked. Server check is best-effort for beta.
    }

    final docRef = policeReportsCollection().doc();

    await docRef.debugSet({
      'uid': firebaseUser.uid,
      'username': currentUser.username,
      'lat': position.latitude,
      'lng': position.longitude,
      'coordinates': GeoPoint(position.latitude, position.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'stillThereBy': <String>[],
      'notThereBy': <String>[],
    });

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    final newReport = PoliceReportData(
      id: docRef.id,
      uid: firebaseUser.uid,
      username: currentUser.username,
      coordinates: location,
      createdAtMillis: now.millisecondsSinceEpoch,
      expiresAtMillis: expiresAt.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
    );

    host.updateMap(() {
      host.currentUserLocation = location;
      host.selectedSpot = null;
      host.selectedPoliceReport = newReport;
      host.selectedSosReport = null;
      host.selectedLiveLocation = null;
      host.isAddingPoliceReport = false;
    });

    host.navigation.moveMapCamera(location, 15.5);

    ScaffoldMessenger.of(viewContext).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: CcsText(
          'Police marked on the map for 2 hours.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Future<void> removePoliceReport(PoliceReportData report) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null ||
        (report.uid != firebaseUser.uid &&
            !userRoleIsStaff(currentUser.role))) {
      return;
    }

    await policeReportsCollection().doc(report.id).debugSet({
      'status': 'removed',
      'removedByUid': firebaseUser.uid,
      'removedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    host.updateMap(() {
      host.selectedPoliceReport = null;
      host.policeReports = host.policeReports
          .where((item) => item.id != report.id)
          .toList();
    });

    ScaffoldMessenger.of(viewContext).showSnackBar(
      SnackBar(
        backgroundColor: panelGlass,
        content: const CcsText(
          'Police mark removed from the map.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Future<void> votePoliceReport(
    PoliceReportData report, {
    required bool stillThere,
  }) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isVotingPoliceReport) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before confirming a police mark.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final position = await host.navigation.getMapUserPosition(showErrors: true);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      return;
    }

    final freshLocation = safeLatLngFromPosition(position);
    if (freshLocation == null) {
      return;
    }
    final distance = const Distance().as(
      LengthUnit.Meter,
      freshLocation,
      report.coordinates,
    );

    host.updateMap(() => host.currentUserLocation = freshLocation);

    if (distance > mapPoliceReportVoteRadiusMeters) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            'Get closer to this police mark before confirming it.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (report.uid == firebaseUser.uid &&
        !isPoliceReportCreatorCooldownOver(report)) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            'You created this mark. You can confirm it later if you drive by this spot again.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    host.updateMap(() => host.isVotingPoliceReport = true);

    final reportRef = policeReportsCollection().doc(report.id);
    var removed = false;

    try {
      await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
        final snapshot = await transaction.debugGet(reportRef);

        if (!snapshot.exists) {
          removed = true;
          return;
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final stillThereBy = List<String>.of(
          stringListFromFirebase(data['stillThereBy'], const []),
        );
        final notThereBy = List<String>.of(
          stringListFromFirebase(data['notThereBy'], const []),
        );

        stillThereBy.remove(firebaseUser.uid);
        notThereBy.remove(firebaseUser.uid);

        if (stillThere) {
          stillThereBy.add(firebaseUser.uid);
        } else {
          notThereBy.add(firebaseUser.uid);
        }

        final shouldRemove =
            !stillThere &&
            (notThereBy.length >= 3 || data['uid'] == firebaseUser.uid);

        if (shouldRemove) {
          removed = true;
          transaction.debugUpdate(reportRef, {
            'status': 'removed',
            'removedByUid': firebaseUser.uid,
            'removedAt': FieldValue.serverTimestamp(),
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.debugUpdate(reportRef, {
            'stillThereBy': stillThereBy,
            'notThereBy': notThereBy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateMap(() => host.isVotingPoliceReport = false);
      }
    }

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (removed) {
      host.updateMap(() {
        host.selectedPoliceReport = null;
        host.policeReports = host.policeReports
            .where((item) => item.id != report.id)
            .toList();
      });

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            'Police mark removed from the map.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: panelGlass,
          content: CcsText(
            stillThere
                ? 'Thanks. Police mark confirmed.'
                : 'Thanks. Not there report saved.',
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
