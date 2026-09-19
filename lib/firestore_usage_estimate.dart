// App-side attribution only. Firestore SDK snapshots do not expose billing.
bool sameFirestoreValue(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameFirestoreValue(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => i,
        ).every((i) => sameFirestoreValue(a[i], b[i]));
  }
  return a == b;
}

class ServerReadEstimate {
  Map<String, Object?>? _server;
  final Map<String, Object?> _pending = {};

  int observe(
    Map<String, Object?> documents, {
    required bool fromCache,
    required bool pendingWrites,
  }) {
    if (pendingWrites) {
      // Remember optimistic data so the acknowledgement is not called a read.
      _pending.addAll(documents);
      return 0;
    }
    if (fromCache) return 0;
    final previous = _server;
    var reads = 0;
    for (final entry in documents.entries) {
      final echo =
          _pending.containsKey(entry.key) &&
          sameFirestoreValue(_pending[entry.key], entry.value);
      if (!echo &&
          (previous == null ||
              !previous.containsKey(entry.key) ||
              !sameFirestoreValue(previous[entry.key], entry.value)))
        reads++;
    }
    // Empty queries still cost a minimum read. Deletions and unchanged metadata
    // are not counted; removals, reconnects and index/rules reads need cloud totals.
    if (previous == null && documents.isEmpty && _pending.isEmpty) reads = 1;
    _pending.clear();
    _server = Map.of(documents);
    return reads;
  }
}
