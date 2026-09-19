import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

class TestBatch extends Fake implements WriteBatch {
  final completion = Completer<void>();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<void> commit() => completion.future;
}

class TestRef extends Fake implements DocumentReference<Map<String, dynamic>> {}

class TestTransaction extends Fake implements Transaction {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class TestDb extends Fake implements FirebaseFirestore {
  bool fail = false;
  @override
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    await handler(TestTransaction()); // First attempt retries, never committed.
    final result = await handler(TestTransaction());
    if (fail) throw StateError('permission denied');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test(
    'queued, failed and successful batch writes count only after acknowledgement',
    () async {
      final before = app.firestoreDebugTracker.totalWrites;
      final failed = TestBatch();
      failed.debugSet(TestRef(), {}, null, 'test failed batch');
      expect(app.firestoreDebugTracker.totalWrites, before);
      final failure = expectLater(failed.debugCommit(), throwsStateError);
      failed.completion.completeError(StateError('rejected'));
      await failure;
      expect(app.firestoreDebugTracker.totalWrites, before);
      final success = TestBatch();
      success.debugSet(TestRef(), {}, null, 'test committed batch');
      final commit = success.debugCommit();
      expect(app.firestoreDebugTracker.totalWrites, before);
      success.completion.complete();
      await commit;
      expect(app.firestoreDebugTracker.totalWrites, before + 1);
      await app.firestoreDebugTracker.flushPersisted();
    },
  );
  test(
    'transaction retries count writes once and failed transactions count none',
    () async {
      final before = app.firestoreDebugTracker.totalWrites;
      final db = TestDb();
      Future<void> write(Transaction tx) async {
        tx.debugSet(TestRef(), {}, null, 'test transaction');
      }

      await db.debugRunTransaction(write);
      expect(app.firestoreDebugTracker.totalWrites, before + 1);
      db.fail = true;
      await expectLater(db.debugRunTransaction(write), throwsStateError);
      expect(app.firestoreDebugTracker.totalWrites, before + 1);
      await app.firestoreDebugTracker.flushPersisted();
    },
  );
}
