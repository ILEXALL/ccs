import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/firestore_usage_estimate.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase;

const bool firestoreDebugTrackerEnabled = true;

class FirestoreDebugStats {
  int reads = 0;
  int writes = 0;
  int deletes = 0;
  int events = 0;
  DateTime? lastAt;

  FirestoreDebugStats();

  factory FirestoreDebugStats.fromJson(Map<String, dynamic> json) {
    return FirestoreDebugStats()
      ..reads = (json['reads'] as num?)?.toInt() ?? 0
      ..writes = (json['writes'] as num?)?.toInt() ?? 0
      ..deletes = (json['deletes'] as num?)?.toInt() ?? 0
      ..events = (json['events'] as num?)?.toInt() ?? 0
      ..lastAt = json['lastAtMillis'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['lastAtMillis'] as num).toInt(),
            )
          : null;
  }

  Map<String, Object?> toJson() {
    return {
      'reads': reads,
      'writes': writes,
      'deletes': deletes,
      'events': events,
      'lastAtMillis': lastAt?.millisecondsSinceEpoch,
    };
  }

  int get total => reads + writes + deletes;
}

class FirestoreDebugEvent {
  final String label;
  final String operation;
  final int count;
  final DateTime at;

  const FirestoreDebugEvent({
    required this.label,
    required this.operation,
    required this.count,
    required this.at,
  });

  factory FirestoreDebugEvent.fromJson(Map<String, dynamic> json) {
    return FirestoreDebugEvent(
      label: stringFromFirebase(json['label'], 'unknown'),
      operation: stringFromFirebase(json['operation'], 'R'),
      count: (json['count'] as num?)?.toInt() ?? 1,
      at: json['atMillis'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['atMillis'] as num).toInt(),
            )
          : DateTime.now(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'label': label,
      'operation': operation,
      'count': count,
      'atMillis': at.millisecondsSinceEpoch,
    };
  }
}

class FirestoreDebugTracker extends ChangeNotifier {
  final Map<String, FirestoreDebugStats> statsByLabel = {};
  final Map<String, FirestoreDebugStats> sessionStatsByLabel = {};
  final List<FirestoreDebugEvent> recentEvents = [];
  DateTime sessionStartedAt = DateTime.now();
  Timer? _persistTimer;
  bool _loadedFromStorage = false;

  Future<void> loadPersisted() async {
    if (_loadedFromStorage) {
      return;
    }

    _loadedFromStorage = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(firestoreDebugTrackerStorageKey);
      if (raw == null || raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final stats = decoded['stats'];
      if (stats is Map) {
        statsByLabel
          ..clear()
          ..addAll({
            for (final entry in stats.entries)
              entry.key.toString(): FirestoreDebugStats.fromJson(
                mapFromFirebase(entry.value),
              ),
          });
      }

      final events = decoded['events'];
      if (events is List) {
        recentEvents
          ..clear()
          ..addAll(
            events
                .whereType<Map>()
                .map(
                  (item) => FirestoreDebugEvent.fromJson(mapFromFirebase(item)),
                )
                .take(80),
          );
      }

      notifyListeners();
    } catch (error) {
      debugPrint('Firestore debug restore failed: $error');
    }
  }

  void recordRead(String label, int count) => _record(label, 'R', count);
  void recordWrite(String label, int count) => _record(label, 'W', count);
  void recordDelete(String label, int count) => _record(label, 'D', count);

  void _record(String label, String operation, int count) {
    if (!firestoreDebugTrackerEnabled || count <= 0) {
      return;
    }

    final cleanLabel = label.trim().isEmpty
        ? 'UNLABELED unknown'
        : label.trim();
    final stats = statsByLabel.putIfAbsent(cleanLabel, FirestoreDebugStats.new);
    final sessionStats = sessionStatsByLabel.putIfAbsent(
      cleanLabel,
      FirestoreDebugStats.new,
    );

    _applyOperation(stats, operation, count);
    _applyOperation(sessionStats, operation, count);

    final now = DateTime.now();
    stats.events += 1;
    stats.lastAt = now;
    sessionStats.events += 1;
    sessionStats.lastAt = now;

    recentEvents.insert(
      0,
      FirestoreDebugEvent(
        label: cleanLabel,
        operation: operation,
        count: count,
        at: now,
      ),
    );
    if (recentEvents.length > 80) {
      recentEvents.removeRange(80, recentEvents.length);
    }

    debugPrint(
      '🔥 FIRESTORE $operation [$cleanLabel]: $count ops '
      '(total R ${stats.reads}, W ${stats.writes}, D ${stats.deletes}; '
      'session R ${sessionStats.reads}, W ${sessionStats.writes}, D ${sessionStats.deletes})',
    );
    notifyListeners();
    _schedulePersist();
  }

  void _applyOperation(FirestoreDebugStats stats, String operation, int count) {
    switch (operation) {
      case 'R':
        stats.reads += count;
        break;
      case 'W':
        stats.writes += count;
        break;
      case 'D':
        stats.deletes += count;
        break;
    }
  }

  void reset() {
    sessionStartedAt = DateTime.now();
    statsByLabel.clear();
    sessionStatsByLabel.clear();
    recentEvents.clear();
    notifyListeners();
    unawaited(_persistNow());
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistNow());
    });
  }

  Future<void> flushPersisted() => _persistNow();

  Future<void> _persistNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        firestoreDebugTrackerStorageKey,
        jsonEncode({
          'stats': {
            for (final entry in statsByLabel.entries)
              entry.key: entry.value.toJson(),
          },
          'events': recentEvents.map((event) => event.toJson()).toList(),
        }),
      );
    } catch (error) {
      debugPrint('Firestore debug persist failed: $error');
    }
  }

  int get totalReads =>
      statsByLabel.values.fold(0, (total, item) => total + item.reads);
  int get totalWrites =>
      statsByLabel.values.fold(0, (total, item) => total + item.writes);
  int get totalDeletes =>
      statsByLabel.values.fold(0, (total, item) => total + item.deletes);

  int get sessionReads =>
      sessionStatsByLabel.values.fold(0, (total, item) => total + item.reads);
  int get sessionWrites =>
      sessionStatsByLabel.values.fold(0, (total, item) => total + item.writes);
  int get sessionDeletes =>
      sessionStatsByLabel.values.fold(0, (total, item) => total + item.deletes);

  bool isUnlabeledLabel(String label) => label.startsWith('UNLABELED ');

  Iterable<MapEntry<String, FirestoreDebugStats>> get unlabeledEntries =>
      statsByLabel.entries.where((entry) => isUnlabeledLabel(entry.key));

  int get unlabeledReads =>
      unlabeledEntries.fold(0, (total, entry) => total + entry.value.reads);
  int get unlabeledWrites =>
      unlabeledEntries.fold(0, (total, entry) => total + entry.value.writes);
  int get unlabeledDeletes =>
      unlabeledEntries.fold(0, (total, entry) => total + entry.value.deletes);
  int get unlabeledEvents =>
      unlabeledEntries.fold(0, (total, entry) => total + entry.value.events);
}

final firestoreDebugTracker = FirestoreDebugTracker();

const firestoreDebugTrackerStorageKey = 'firestore_debug_tracker_server_v2';

Future<QuerySnapshot<Map<String, dynamic>>> trackedQueryGet(
  String label,
  Query<Map<String, dynamic>> query, [
  GetOptions? options,
]) => query.debugGet(options, label);

Future<DocumentSnapshot<Map<String, dynamic>>> trackedDocGet(
  String label,
  DocumentReference<Map<String, dynamic>> ref, [
  GetOptions? options,
]) => ref.debugGet(options, label);

Stream<QuerySnapshot<Map<String, dynamic>>> trackedQuerySnapshots(
  String label,
  Query<Map<String, dynamic>> query, {
  bool includeMetadataChanges = false,
}) => observedQuerySnapshots(
  query,
  label,
  includeMetadataChanges: includeMetadataChanges,
);

Stream<DocumentSnapshot<Map<String, dynamic>>> trackedDocSnapshots(
  String label,
  DocumentReference<Map<String, dynamic>> ref,
) => observedDocSnapshots(ref, label);

int firestoreDebugBillableQueryReadCount(int documentCount) =>
    math.max(1, documentCount);

Stream<QuerySnapshot<T>> observedQuerySnapshots<T extends Object?>(
  Query<T> query,
  String label, {
  bool includeMetadataChanges = false,
}) => Stream<QuerySnapshot<T>>.multi((sink) {
  final subscription = _observedQuerySnapshots(
    query,
    label,
    includeMetadataChanges: includeMetadataChanges,
  ).listen(sink.add, onError: sink.addError, onDone: sink.close);
  sink.onCancel = subscription.cancel;
}, isBroadcast: true);

Stream<QuerySnapshot<T>> _observedQuerySnapshots<T extends Object?>(
  Query<T> query,
  String label, {
  bool includeMetadataChanges = false,
}) async* {
  final estimate = ServerReadEstimate();
  Map<String, Object?>? delivered;
  await for (final snapshot in query.snapshots(includeMetadataChanges: true)) {
    final data = {for (final doc in snapshot.docs) doc.id: doc.data()};
    firestoreDebugTracker.recordRead(
      label,
      estimate.observe(
        data,
        fromCache: snapshot.metadata.isFromCache,
        pendingWrites: snapshot.metadata.hasPendingWrites,
      ),
    );
    // Observe server acknowledgements internally without adding metadata-only
    // callbacks to application listeners that did not request them.
    if (includeMetadataChanges ||
        delivered == null ||
        !sameFirestoreValue(delivered, data) ||
        delivered.keys.join('|') != data.keys.join('|')) {
      delivered = data;
      yield snapshot;
    }
  }
}

Stream<DocumentSnapshot<T>> observedDocSnapshots<T extends Object?>(
  DocumentReference<T> ref,
  String label,
) => Stream<DocumentSnapshot<T>>.multi((sink) {
  final subscription = _observedDocSnapshots(
    ref,
    label,
  ).listen(sink.add, onError: sink.addError, onDone: sink.close);
  sink.onCancel = subscription.cancel;
}, isBroadcast: true);

Stream<DocumentSnapshot<T>> _observedDocSnapshots<T extends Object?>(
  DocumentReference<T> ref,
  String label,
) async* {
  final estimate = ServerReadEstimate();
  Object? delivered;
  var first = true;
  await for (final snapshot in ref.snapshots(includeMetadataChanges: true)) {
    final data = snapshot.data();
    firestoreDebugTracker.recordRead(
      label,
      estimate.observe(
        {ref.id: data},
        fromCache: snapshot.metadata.isFromCache,
        pendingWrites: snapshot.metadata.hasPendingWrites,
      ),
    );
    if (first || !sameFirestoreValue(delivered, data)) {
      first = false;
      delivered = data;
      yield snapshot;
    }
  }
}

final _queuedDebugOperations = Expando<List<void Function()>>();

void queueDebugOperation(Object owner, void Function() operation) {
  (_queuedDebugOperations[owner] ??= []).add(operation);
}

void confirmDebugOperations(Object owner) {
  final operations = _queuedDebugOperations[owner] ?? [];
  _queuedDebugOperations[owner] = null;
  for (final operation in operations) {
    operation();
  }
}

extension ConfirmedFirestoreTransaction on FirebaseFirestore {
  Future<T> debugRunTransaction<T>(
    Future<T> Function(Transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    Transaction? last;
    final result = await runTransaction<T>(
      (transaction) {
        last = transaction;
        _queuedDebugOperations[transaction] = [];
        return handler(transaction);
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    if (last != null) confirmDebugOperations(last!);
    return result;
  }
}

String firestoreDebugTargetLabel(Object target) {
  if (target is DocumentReference) {
    return target.path;
  }

  if (target is CollectionReference) {
    return target.path;
  }

  var value = target.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length > 96) {
    value = '${value.substring(0, 96)}...';
  }

  return value.isEmpty ? target.runtimeType.toString() : value;
}

String firestoreDebugCallerLabel(
  String operation,
  Object target, [
  String? label,
]) {
  if (label != null && label.trim().isNotEmpty) {
    return label.trim();
  }

  final frames = StackTrace.current.toString().split('\n');
  var caller = '';

  for (final frame in frames) {
    final cleanFrame = frame.trim();
    if (cleanFrame.isEmpty ||
        cleanFrame.contains('firestoreDebugCallerLabel') ||
        cleanFrame.contains('debugGet') ||
        cleanFrame.contains('debugSnapshots') ||
        cleanFrame.contains('debugSet') ||
        cleanFrame.contains('debugUpdate') ||
        cleanFrame.contains('debugDelete') ||
        cleanFrame.contains('debugCommit') ||
        cleanFrame.contains('trackedQueryGet') ||
        cleanFrame.contains('trackedDocGet') ||
        cleanFrame.contains('trackedQuerySnapshots') ||
        cleanFrame.contains('trackedDocSnapshots')) {
      continue;
    }

    caller = cleanFrame;
    break;
  }

  final targetLabel = firestoreDebugTargetLabel(target);
  return caller.isEmpty
      ? 'UNLABELED $operation • $targetLabel'
      : 'UNLABELED $operation • $targetLabel • $caller';
}

extension FirestoreDebugQueryExtension<T extends Object?> on Query<T> {
  Future<QuerySnapshot<T>> debugGet([
    GetOptions? options,
    String? label,
  ]) async {
    final debugLabel = firestoreDebugCallerLabel('query.get', this, label);
    final snapshot = await get(options);
    if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites) {
      firestoreDebugTracker.recordRead(
        debugLabel,
        firestoreDebugBillableQueryReadCount(snapshot.docs.length),
      );
    }
    return snapshot;
  }

  Stream<QuerySnapshot<T>> debugSnapshots([String? label]) {
    final debugLabel = firestoreDebugCallerLabel(
      'query.snapshots',
      this,
      label,
    );
    return observedQuerySnapshots(this, debugLabel);
  }
}

extension FirestoreDebugDocumentReferenceExtension<T extends Object?>
    on DocumentReference<T> {
  Future<DocumentSnapshot<T>> debugGet([
    GetOptions? options,
    String? label,
  ]) async {
    final debugLabel = firestoreDebugCallerLabel('doc.get', this, label);
    final snapshot = await get(options);
    if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites)
      firestoreDebugTracker.recordRead(debugLabel, 1);
    return snapshot;
  }

  Stream<DocumentSnapshot<T>> debugSnapshots([String? label]) {
    final debugLabel = firestoreDebugCallerLabel('doc.snapshots', this, label);

    return observedDocSnapshots(this, debugLabel);
  }

  Future<void> debugSet(T data, [SetOptions? options, String? label]) async {
    final debugLabel = firestoreDebugCallerLabel('doc.set', this, label);
    await set(data, options);
    firestoreDebugTracker.recordWrite(debugLabel, 1);
  }

  Future<void> debugUpdate(Map<Object, Object?> data, [String? label]) async {
    final debugLabel = firestoreDebugCallerLabel('doc.update', this, label);
    await update(data);
    firestoreDebugTracker.recordWrite(debugLabel, 1);
  }

  Future<void> debugDelete([String? label]) async {
    final debugLabel = firestoreDebugCallerLabel('doc.delete', this, label);
    await delete();
    firestoreDebugTracker.recordDelete(debugLabel, 1);
  }
}

extension FirestoreDebugTransactionExtension on Transaction {
  Future<DocumentSnapshot<T>> debugGet<T extends Object?>(
    DocumentReference<T> ref, [
    String? label,
  ]) async {
    final debugLabel = firestoreDebugCallerLabel('transaction.get', ref, label);
    final snapshot = await get(ref);
    if (!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites)
      firestoreDebugTracker.recordRead(debugLabel, 1);
    return snapshot;
  }

  Transaction debugSet<T extends Object?>(
    DocumentReference<T> ref,
    T data, [
    SetOptions? options,
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel('transaction.set', ref, label);
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordWrite(debugLabel, 1),
    );
    set(ref, data, options);
    return this;
  }

  Transaction debugUpdate<T extends Object?>(
    DocumentReference<T> ref,
    Map<Object, Object?> data, [
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel(
      'transaction.update',
      ref,
      label,
    );
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordWrite(debugLabel, 1),
    );
    update(ref, data);
    return this;
  }

  Transaction debugDelete<T extends Object?>(
    DocumentReference<T> ref, [
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel(
      'transaction.delete',
      ref,
      label,
    );
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordDelete(debugLabel, 1),
    );
    delete(ref);
    return this;
  }
}

extension FirestoreDebugCollectionReferenceExtension<T extends Object?>
    on CollectionReference<T> {
  Future<DocumentReference<T>> debugAdd(T data, [String? label]) async {
    final debugLabel = firestoreDebugCallerLabel('collection.add', this, label);
    final ref = await add(data);
    firestoreDebugTracker.recordWrite(debugLabel, 1);
    return ref;
  }
}

extension FirestoreDebugWriteBatchExtension on WriteBatch {
  Future<void> debugCommit() async {
    await commit();
    confirmDebugOperations(this);
  }

  void debugSet<T extends Object?>(
    DocumentReference<T> ref,
    T data, [
    SetOptions? options,
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel('batch.set', ref, label);
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordWrite(debugLabel, 1),
    );
    set(ref, data, options);
  }

  void debugUpdate<T extends Object?>(
    DocumentReference<T> ref,
    Map<Object, Object?> data, [
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel('batch.update', ref, label);
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordWrite(debugLabel, 1),
    );
    update(ref, data);
  }

  void debugDelete<T extends Object?>(
    DocumentReference<T> ref, [
    String? label,
  ]) {
    final debugLabel = firestoreDebugCallerLabel('batch.delete', ref, label);
    queueDebugOperation(
      this,
      () => firestoreDebugTracker.recordDelete(debugLabel, 1),
    );
    delete(ref);
  }
}
