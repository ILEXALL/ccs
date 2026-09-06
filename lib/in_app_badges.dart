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
  final forumCategories = <String, String>{};
  int topicCount(String key) => counts[key] ?? 0;
  int forumCount(String country, {String? category}) => forumCategories.entries
      .where(
        (entry) =>
            entry.key.startsWith('forum/$country/') &&
            (category == null || entry.value == category),
      )
      .fold(0, (total, entry) => total + topicCount(entry.key));
  int topicSeen(String key) => seenAt[key] ?? seenAt['forum'] ?? since;
  void readTopic(String key, int now) {
    if (now > topicSeen(key)) seenAt[key] = now;
    counts[key] = 0;
  }

  void receiveTopic(String key, int time, {required bool own}) {
    if (!own && time > topicSeen(key)) counts[key] = topicCount(key) + 1;
  }

  int count(ActivitySection section) => counts[section.name] ?? 0;
  int get chatCount =>
      ActivitySection.values.take(4).fold(0, (n, s) => n + count(s));
  void visit(ActivitySection section, int now) {
    if (section == ActivitySection.forum) return;
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
    'forumCategories': forumCategories,
  };
  factory ActivityBadgeState.restore(Map<String, dynamic> data, int now) {
    final result = ActivityBadgeState((data['since'] as num?)?.toInt() ?? now);
    if (data['forumCategories'] is Map) {
      (data['forumCategories'] as Map).forEach((key, value) {
        if (value is String) result.forumCategories[key.toString()] = value;
      });
    }
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
    // One-time migration: old aggregate unread counts did not identify topics.
    // Replay only unread forum activity so existing badges can be attributed.
    if (data['forumCategories'] is! Map &&
        result.count(ActivitySection.forum) > 0) {
      result.cursors.removeWhere((key, _) => key.startsWith('forum/'));
      result.summaries.removeWhere((key, _) => key.startsWith('forum/'));
    }
    return result;
  }
}

class InAppBadgeController extends ChangeNotifier {
  final FirebaseFirestore db;
  InAppBadgeController(this.db, {this.onRead, this.forumCategoryForData});
  final void Function(String, int)? onRead;
  final String Function(Map<String, dynamic>)? forumCategoryForData;
  ActivityBadgeState state = ActivityBadgeState(
    DateTime.now().millisecondsSinceEpoch,
  );
  String? _uid;
  String _countryCode = 'LV';
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

  String? _visibleForumTopic;
  bool Function()? _forumPageVisible;
  String topicKey(String topicId, String country) => 'forum/$country/$topicId';
  int forumTopicCount(String topicId, String country) =>
      state.topicCount(topicKey(topicId, country));
  int forumCategoryCount(String category) =>
      state.forumCount(_countryCode, category: category);
  int count(ActivitySection section) => section == ActivitySection.forum
      ? state.forumCount(_countryCode)
      : state.count(section);
  int get chatCount => ActivitySection.values
      .take(4)
      .fold(0, (total, section) => total + count(section));
  void openForumTopic(
    String topicId,
    String country, {
    bool Function()? isVisible,
  }) {
    _visibleForumTopic = topicKey(topicId, country);
    _forumPageVisible = isVisible;
    if (!_ready) return;
    state.readTopic(_visibleForumTopic!, DateTime.now().millisecondsSinceEpoch);
    _changed();
  }

  void closeForumTopic(String topicId) {
    if (_visibleForumTopic?.endsWith('/$topicId') == true) {
      _visibleForumTopic = null;
      _forumPageVisible = null;
    }
  }

  Future<void> start(String uid, {String countryCode = 'LV'}) async {
    final cleanCountryCode = countryCode.trim().toUpperCase();
    if (_uid == uid && _countryCode == cleanCountryCode) return;
    stop();
    _uid = uid;
    _countryCode = cleanCountryCode.isEmpty ? 'LV' : cleanCountryCode;
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
          .where('countryCode', isEqualTo: _countryCode)
          .orderBy('timestamp', descending: true)
          .limit(1),
      (snapshot) {
        if (snapshot.docs.isNotEmpty) {
          _schedule(
            'global/$_countryCode',
            snapshot.docs.first.data()['timestamp'],
            ActivitySection.global,
            db.collection('global_chat'),
            'timestamp',
            'userId',
            countryCode: _countryCode,
          );
        }
      },
    );
    Query<Map<String, dynamic>> forumTopicsQuery = db
        .collection('forum_topics')
        .where('status', isEqualTo: 'approved');
    if (_countryCode != 'LV') {
      forumTopicsQuery = forumTopicsQuery.where(
        'countryCode',
        isEqualTo: _countryCode,
      );
    }
    _watch(forumTopicsQuery, (snapshot) {
      final activeKeys = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final topicCountryCode = (data['countryCode'] as String?)
            ?.trim()
            .toUpperCase();
        // Untagged topics are legacy content from the original Latvian
        // community.
        if ((topicCountryCode?.isNotEmpty == true ? topicCountryCode : 'LV') !=
            _countryCode) {
          continue;
        }
        final expiry = data['autoExpiresAt'];
        if (expiry is Timestamp &&
            expiry.millisecondsSinceEpoch <=
                DateTime.now().millisecondsSinceEpoch) {
          continue;
        }
        final key = topicKey(doc.id, _countryCode);
        activeKeys.add(key);
        state.forumCategories[key] =
            forumCategoryForData?.call(data) ??
            (data['categoryId'] ?? data['category'] ?? 'meets_events')
                .toString();
        _schedule(
          key,
          data['lastReplyAt'],
          ActivitySection.forum,
          doc.reference.collection('replies'),
          'timestamp',
          'userId',
        );
      }
      state.forumCategories.removeWhere(
        (key, _) =>
            key.startsWith('forum/$_countryCode/') && !activeKeys.contains(key),
      );
      _changed();
    });
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
    String authorField, {
    String countryCode = '',
  }) {
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
        countryCode: countryCode,
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
    int generation, {
    String countryCode = '',
  }) async {
    while (generation == _generation) {
      Query<Map<String, dynamic>> query = collection
          .orderBy(timeField)
          .orderBy(FieldPath.documentId);
      if (countryCode.isNotEmpty) {
        query = query.where('countryCode', isEqualTo: countryCode);
      }
      final cursor = state.cursors[key];
      final seen = section == ActivitySection.forum
          ? state.topicSeen(key)
          : state.seenAt[section.name] ?? state.since;
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
        if (section == ActivitySection.forum) {
          if (_visibleForumTopic == key &&
              (_forumPageVisible?.call() ?? false)) {
            state.readTopic(key, stamp.millisecondsSinceEpoch);
          } else {
            state.receiveTopic(
              key,
              stamp.millisecondsSinceEpoch,
              own: data[authorField] == _uid,
            );
          }
        } else if (visibleSection != section) {
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
    _visibleForumTopic = null;
    _forumPageVisible = null;
    _lastChats = null;
    _ready = false;
    _uid = null;
  }
}
