import 'package:ccs_app/core/firestore/collections.dart';
import 'package:ccs_app/core/firestore/firestore_tracking.dart';
import 'package:ccs_app/core/firestore/firestore_usage_estimate.dart';

import '../models/xp_stats.dart';

Stream<int> watchConfirmedLevel(String uid) async* {
  final estimate = ServerReadEstimate();
  await for (final snapshot
      in xpUserStatsCollection()
          .doc(uid)
          .snapshots(includeMetadataChanges: true)) {
    firestoreDebugTracker.recordRead(
      'progression: level-up feedback listener',
      estimate.observe(
        {snapshot.id: snapshot.data()},
        fromCache: snapshot.metadata.isFromCache,
        pendingWrites: snapshot.metadata.hasPendingWrites,
      ),
    );
    // Cache can be older than an already completed celebration. Metadata
    // updates are required even if server data matches the cached data.
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      continue;
    }
    yield snapshot.exists ? XpUserStats.fromFirestore(snapshot).level : 1;
  }
}
