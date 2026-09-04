import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActivitySection { direct, groups, global, forum, spots, map }

// Local UI state only: never writes notification documents or OS badges.
class ActivityBadgeState {
  ActivityBadgeState(this.since);
  final int since;
  final counts = <String, int>{};
  final seenAt = <String, int>{};
  final cursors = <String, List<dynamic>>{};
  final summaries = <String, String>{};
  final spotIds = <String>{};
  int count(ActivitySection section) => counts[section.name] ?? 0;
  int get chatCount =>
      ActivitySection.values.take(4).fold(0, (n, s) => n + count(s));
  void visit(ActivitySection section, int now) {
    seenAt[section.name] = now;
    counts[section.name] = 0;
  }

  void receive(ActivitySection section, int time, {required bool own}) {
    if (!own && time > (seenAt[section.name] ?? since)) {
      counts[section.name] = count(section) + 1;
    }
  }

  Map<String, dynamic> toJson() => {
    'since': since,
    'counts': counts,
    'seenAt': seenAt,
    'cursors': cursors,
    'summaries': summaries,
    'spotIds': spotIds.toList(),
  };
  factory ActivityBadgeState.restore(Map<String, dynamic> data, int now) {
    final result = ActivityBadgeState((data['since'] as num?)?.toInt() ?? now);
    for (final pair in [
      (data['counts'], result.counts),
      (data['seenAt'], result.seenAt),
    ]) {
      if (pair.$1 is Map) {
        (pair.$1 as Map).forEach((k, v) {
          if (v is num) pair.$2[k.toString()] = v.toInt();
        });
      }
    }
    if (data['cursors'] is Map) {
      (data['cursors'] as Map).forEach((k, v) {
        if (v is List &&
            v.length == 3 &&
            v[0] is int &&
            v[1] is int &&
            v[2] is String) {
          result.cursors[k.toString()] = List<dynamic>.from(v);
        }
      });
    }
    if (data['summaries'] is Map) {
      (data['summaries'] as Map).forEach((k, v) {
        if (v is String) result.summaries[k.toString()] = v;
      });
    }
    if (data['spotIds'] is List) {
      result.spotIds.addAll((data['spotIds'] as List).whereType<String>());
    }
    return result;
  }
}

class InAppBadgeController extends ChangeNotifier {
  final FirebaseFirestore db;
  InAppBadgeController(this.db, {this.onRead});
  final void Function(String, int)? onRead;
  ActivityBadgeState state = ActivityBadgeState(
    DateTime.now().millisecondsSinceEpoch,
  );
  String? _uid;
  int _generation = 0;
  bool _ready = false;
  final _subscriptions = <StreamSubscription>[];
  final _pending = <String, Future<void> Function(int)>{};
  bool _draining = false;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();
  final _chatEvents =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  QuerySnapshot<Map<String, dynamic>>? _lastChats;
  final _summaryVersions = <String, String>{};
  ActivitySection? visibleSection;
  void Function()? onReady;
  String? get uid => _uid;
  Stream<QuerySnapshot<Map<String, dynamic>>> get chats async* {
    if (_lastChats != null) yield _lastChats!;
    yield* _chatEvents.stream;
  }

  int count(ActivitySection section) => state.count(section);
  int get chatCount => state.chatCount;

  Future<void> start(String uid) async {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    final generation = _generation;
    await _saving.catchError((Object _) {});
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      state = ActivityBadgeState.restore(
        jsonDecode(prefs.getString('activity_badges_v1_$uid') ?? '{}')
            as Map<String, dynamic>,
        now,
      );
    } catch (_) {
      state = ActivityBadgeState(now);
    }
    _ready = true;
    if (visibleSection != null) state.visit(visibleSection!, now);
    _changed();
    _watch(
      db.collection('chats').where('memberIds', arrayContains: uid),
      (snapshot) {
        _lastChats = snapshot;
        _chatEvents.add(snapshot);
        if (snapshot.metadata.isFromCache ||
            snapshot.metadata.hasPendingWrites) {
          return;
        }
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if ((data['hiddenForUserIds'] as List?)?.contains(uid) == true) {
            continue;
          }
          _schedule(
            'chat/${doc.id}',
            data['updatedAt'],
            data['isGroup'] == true
                ? ActivitySection.groups
                : ActivitySection.direct,
            doc.reference.collection('messages'),
            'createdAt',
            'senderUid',
          );
        }
      },
      includeCache: true,
    );
    _watch(
      db
          .collection('global_chat')
          .orderBy('timestamp', descending: true)
          .limit(1),
      (snapshot) {
        if (snapshot.docs.isNotEmpty) {
          _schedule(
            'global',
            snapshot.docs.first.data()['timestamp'],
            ActivitySection.global,
            db.collection('global_chat'),
            'timestamp',
            'userId',
          );
        }
      },
    );
    _watch(
      db.collection('forum_topics').where('status', isEqualTo: 'approved'),
      (snapshot) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final expiry = data['autoExpiresAt'];
          if (expiry is Timestamp &&
              expiry.millisecondsSinceEpoch <=
                  DateTime.now().millisecondsSinceEpoch) {
            continue;
          }
          _schedule(
            'forum/${doc.id}',
            data['lastReplyAt'],
            ActivitySection.forum,
            doc.reference.collection('replies'),
            'timestamp',
            'userId',
          );
        }
      },
    );
    onReady?.call();
  }

  void _watch(
    Query<Map<String, dynamic>> query,
    void Function(QuerySnapshot<Map<String, dynamic>>) receive, {
    bool includeCache = false,
  }) {
    final generation = _generation;
    var firstServerSnapshot = true;
    _subscriptions.add(
      query.snapshots(includeMetadataChanges: true).listen(
        (snapshot) {
          if (generation != _generation ||
              (!includeCache &&
                  (snapshot.metadata.isFromCache ||
                      snapshot.metadata.hasPendingWrites))) {
            return;
          }
          if (!snapshot.metadata.isFromCache &&
              !snapshot.metadata.hasPendingWrites) {
            if (onRead != null) {
              onRead!(
                'in-app badges: activity summaries',
                firstServerSnapshot
                    ? (snapshot.docs.isEmpty ? 1 : snapshot.docs.length)
                    : snapshot.docChanges.length,
              );
            }
            firstServerSnapshot = false;
          }
          receive(snapshot);
        },
        onError: (Object error) =>
            debugPrint('In-app activity listener: $error'),
      ),
    );
  }

  void _schedule(
    String key,
    dynamic updated,
    ActivitySection section,
    CollectionReference<Map<String, dynamic>> collection,
    String timeField,
    String authorField,
  ) {
    if (updated is! Timestamp ||
        updated.millisecondsSinceEpoch <= state.since) {
      return;
    }
    final version = '${updated.seconds}:${updated.nanoseconds}';
    if (_summaryVersions[key] == version || state.summaries[key] == version) {
      return;
    }
    _summaryVersions[key] = version;
    _pending[key] = (generation) async {
      await _readNewMessages(
        key,
        section,
        collection,
        timeField,
        authorField,
        generation,
      );
      if (generation == _generation) {
        state.summaries[key] = version;
        _changed();
      }
    };
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    final generation = _generation;
    try {
      while (_pending.isNotEmpty && generation == _generation) {
        final key = _pending.keys.first;
        final job = _pending.remove(key)!;
        try {
          await job(generation);
        } catch (error) {
          // Retry on the next summary change/resume, never in a tight loop.
          _summaryVersions.remove(key);
          debugPrint('In-app activity fetch: $error');
        }
      }
    } finally {
      _draining = false;
      if (_pending.isNotEmpty) unawaited(_drain());
    }
  }

  Future<void> _readNewMessages(
    String key,
    ActivitySection section,
    CollectionReference<Map<String, dynamic>> collection,
    String timeField,
    String authorField,
    int generation,
  ) async {
    while (generation == _generation) {
      Query<Map<String, dynamic>> query = collection
          .orderBy(timeField)
          .orderBy(FieldPath.documentId);
      final cursor = state.cursors[key];
      final seen = state.seenAt[section.name] ?? state.since;
      final skipSeen =
          cursor == null ||
          Timestamp(cursor[0] as int, cursor[1] as int).millisecondsSinceEpoch <
              seen;
      query = skipSeen
          ? query.where(
              timeField,
              isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(seen),
            )
          : query.startAfter([
              Timestamp(cursor[0] as int, cursor[1] as int),
              cursor[2],
            ]);
      final snapshot = await query
          .limit(100)
          .get(const GetOptions(source: Source.server));
      onRead?.call(
        'in-app badges: new messages ($key)',
        snapshot.docs.isEmpty ? 1 : snapshot.docs.length,
      );
      if (generation != _generation) return;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final stamp = data[timeField];
        if (stamp is! Timestamp) continue;
        if (visibleSection != section) {
          state.receive(
            section,
            stamp.millisecondsSinceEpoch,
            own: data[authorField] == _uid,
          );
        }
        state.cursors[key] = [stamp.seconds, stamp.nanoseconds, doc.id];
      }
      if (snapshot.docs.isNotEmpty) _changed();
      if (snapshot.docs.length < 100) return;
    }
  }

  void visit(ActivitySection? section) {
    visibleSection = section;
    if (!_ready || section == null) return;
    state.visit(section, DateTime.now().millisecondsSinceEpoch);
    _changed();
  }

  // Reuses approved spots already loaded by the app, with no extra query.
  void observeSpot(
    String id,
    int created, {
    required bool own,
    required bool eligible,
  }) {
    if (!_ready || !eligible || id.isEmpty || !state.spotIds.add(id)) return;
    for (final section in [ActivitySection.spots, ActivitySection.map]) {
      if (visibleSection != section) state.receive(section, created, own: own);
    }
    _changed();
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _persist);
  }

  void _persist() {
    if (!_ready || _uid == null) return;
    final key = 'activity_badges_v1_$_uid';
    final value = jsonEncode(state.toJson());
    _saving = _saving.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    });
  }

  void stop() {
    _persist();
    _generation++;
    _saveTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _pending.clear();
    _summaryVersions.clear();
    _lastChats = null;
    _ready = false;
    _uid = null;
  }
}
