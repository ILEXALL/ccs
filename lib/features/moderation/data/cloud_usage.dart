import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/config/app_config.dart' show firestoreUsageUrl;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, mapFromFirebase, stringFromFirebase;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class FirestoreCloudUsageSnapshot {
  final int reads;
  final int writes;
  final int deletes;
  final int queryReads;
  final int lookupReads;
  final int activeConnections;
  final int snapshotListeners;
  final DateTime? generatedAt;
  final String windowLabel;

  const FirestoreCloudUsageSnapshot({
    required this.reads,
    required this.writes,
    required this.deletes,
    required this.queryReads,
    required this.lookupReads,
    required this.activeConnections,
    required this.snapshotListeners,
    required this.generatedAt,
    required this.windowLabel,
  });

  factory FirestoreCloudUsageSnapshot.fromJson(Map<String, dynamic> json) {
    final totals = mapFromFirebase(json['totals']);
    final readTypes = mapFromFirebase(json['readTypes']);
    final network = mapFromFirebase(json['network']);
    final generatedAtMillis = (json['generatedAtMillis'] as num?)?.toInt();

    return FirestoreCloudUsageSnapshot(
      reads: intFromFirebase(totals['reads'], 0),
      writes: intFromFirebase(totals['writes'], 0),
      deletes: intFromFirebase(totals['deletes'], 0),
      queryReads: intFromFirebase(readTypes['query'], 0),
      lookupReads: intFromFirebase(readTypes['lookup'], 0),
      activeConnections: intFromFirebase(network['activeConnections'], 0),
      snapshotListeners: intFromFirebase(network['snapshotListeners'], 0),
      generatedAt: generatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(generatedAtMillis),
      windowLabel: stringFromFirebase(json['window'], 'Today'),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'reads': reads,
      'writes': writes,
      'deletes': deletes,
      'queryReads': queryReads,
      'lookupReads': lookupReads,
      'activeConnections': activeConnections,
      'snapshotListeners': snapshotListeners,
      'generatedAtMillis': generatedAt?.millisecondsSinceEpoch,
      'windowLabel': windowLabel,
    };
  }

  factory FirestoreCloudUsageSnapshot.fromBaselineJson(
    Map<String, dynamic> json,
  ) {
    return FirestoreCloudUsageSnapshot(
      reads: intFromFirebase(json['reads'], 0),
      writes: intFromFirebase(json['writes'], 0),
      deletes: intFromFirebase(json['deletes'], 0),
      queryReads: intFromFirebase(json['queryReads'], 0),
      lookupReads: intFromFirebase(json['lookupReads'], 0),
      activeConnections: intFromFirebase(json['activeConnections'], 0),
      snapshotListeners: intFromFirebase(json['snapshotListeners'], 0),
      generatedAt: json['generatedAtMillis'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['generatedAtMillis'] as num).toInt(),
            )
          : null,
      windowLabel: stringFromFirebase(json['windowLabel'], 'Today'),
    );
  }

  static const zero = FirestoreCloudUsageSnapshot(
    reads: 0,
    writes: 0,
    deletes: 0,
    queryReads: 0,
    lookupReads: 0,
    activeConnections: 0,
    snapshotListeners: 0,
    generatedAt: null,
    windowLabel: 'Today',
  );
}

class FirestoreCloudUsageController extends ChangeNotifier {
  FirestoreCloudUsageSnapshot? snapshot;
  FirestoreCloudUsageSnapshot baseline = FirestoreCloudUsageSnapshot.zero;
  bool isLoading = false;
  String? errorMessage;
  DateTime? lastFetchedAt;

  Future<void> loadBaseline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(firestoreCloudUsageBaselineStorageKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        baseline = FirestoreCloudUsageSnapshot.fromBaselineJson(decoded);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Firestore cloud usage baseline restore failed: $error');
    }
  }

  Future<void> refresh() async {
    if (currentUser.role != UserRole.admin) return;
    if (isLoading) {
      return;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(firestoreUsageUrl);
      final client = HttpClient();
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token == null) throw StateError('Admin sign-in required');
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final failure = jsonDecode(body);
          throw StateError(
            failure is Map
                ? '${failure['error'] ?? 'Cloud usage unavailable'}'
                : 'Cloud usage unavailable',
          );
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Usage endpoint returned invalid JSON.');
        }

        if (decoded['ok'] == false) {
          throw StateError(
            stringFromFirebase(decoded['error'], 'Usage endpoint failed.'),
          );
        }

        snapshot = FirestoreCloudUsageSnapshot.fromJson(decoded);
        lastFetchedAt = DateTime.now();
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      errorMessage = '$error';
      debugPrint('Firestore cloud usage refresh failed: $error');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetBaselineToCurrent() async {
    if (snapshot == null) {
      await refresh();
    }

    final current = snapshot;
    if (current == null) {
      return;
    }

    baseline = current;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        firestoreCloudUsageBaselineStorageKey,
        jsonEncode(baseline.toJson()),
      );
    } catch (error) {
      debugPrint('Firestore cloud usage baseline save failed: $error');
    }
  }

  int get readsSinceReset =>
      math.max(0, (snapshot?.reads ?? 0) - baseline.reads);
  int get writesSinceReset =>
      math.max(0, (snapshot?.writes ?? 0) - baseline.writes);
  int get deletesSinceReset =>
      math.max(0, (snapshot?.deletes ?? 0) - baseline.deletes);
  int get queryReadsSinceReset =>
      math.max(0, (snapshot?.queryReads ?? 0) - baseline.queryReads);
  int get lookupReadsSinceReset =>
      math.max(0, (snapshot?.lookupReads ?? 0) - baseline.lookupReads);
}

final firestoreCloudUsageController = FirestoreCloudUsageController();

const firestoreCloudUsageBaselineStorageKey =
    'firestore_cloud_usage_baseline_ops_v2';
