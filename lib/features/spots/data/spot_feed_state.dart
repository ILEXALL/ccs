import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanUseVerifiedOnlySpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
spotSyncSubscriptions = [];

final Map<String, Map<String, CarSpot>> firebaseSpotCacheBySource = {};

int spotSyncGeneration = 0;

String? spotSyncScope;

final Set<String> spotSourcesWithServerSnapshot = {};

String get currentSpotSyncScope =>
    '${currentUser.uid}_${currentUserCanUseVerifiedOnlySpots ? 'verified' : 'public'}';

bool spotSyncIsCurrent(int generation, String scope) {
  return generation == spotSyncGeneration &&
      scope == spotSyncScope &&
      scope == currentSpotSyncScope &&
      FirebaseAuth.instance.currentUser?.uid == currentUser.uid &&
      !currentUser.banActive;
}
