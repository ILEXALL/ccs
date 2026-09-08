import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/in_app_badges.dart';

// Controller tests use empty summary streams and the real local persistence
// path, without a Firebase app or network connection.
class _FirestoreStub extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _EmptyCollection();
}

// Test-only stand-in; production code uses Firestore's query implementation.
// ignore: subtype_of_sealed_class
class _EmptyCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if ([#where, #orderBy, #limit].contains(invocation.memberName)) return this;
    if (invocation.memberName == #snapshots) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'displayed replies clear topic, category and navigation badges immediately',
    () {
      final controller = InAppBadgeController(_FirestoreStub());
      addTearDown(() {
        controller.stop();
        controller.dispose();
      });
      controller.state = ActivityBadgeState(0);
      controller.state.forumCategories['forum/LV/a'] = 'meets_events';
      controller.state.receiveTopic('forum/LV/a', 1, own: false);
      var notified = false;
      controller.addListener(() {
        notified = true;
        expect(controller.forumTopicCount('a', 'LV'), 0);
        expect(controller.forumCategoryCount('meets_events'), 0);
        expect(controller.chatCount, 0);
      });
      controller.openForumTopic('a', 'LV', isVisible: () => true);
      expect(notified, isTrue);
    },
  );

  test(
    'reads during restore survive closing the page and are persisted',
    () async {
      final stored = ActivityBadgeState(0);
      stored.forumCategories['forum/LV/a'] = 'meets_events';
      stored.receiveTopic('forum/LV/a', 1, own: false);
      SharedPreferences.setMockInitialValues({
        'activity_badges_v1_user': jsonEncode(stored.toJson()),
      });
      final controller = InAppBadgeController(_FirestoreStub());
      addTearDown(() {
        controller.stop();
        controller.dispose();
      });
      final startup = controller.start('user');
      controller.openForumTopic('a', 'LV', isVisible: () => true);
      controller.closeForumTopic('a');
      await startup;
      expect(controller.forumTopicCount('a', 'LV'), 0);
      expect(controller.chatCount, 0);
      controller.stop();
      await controller.start('user');
      expect(controller.forumTopicCount('a', 'LV'), 0);
    },
  );

  test('a read before controller startup is not lost', () async {
    final stored = ActivityBadgeState(0);
    stored.counts['forum/LV/a'] = 3;
    stored.forumCategories['forum/LV/a'] = 'meets_events';
    SharedPreferences.setMockInitialValues({
      'activity_badges_v1_user': jsonEncode(stored.toJson()),
    });
    final controller = InAppBadgeController(_FirestoreStub());
    addTearDown(() {
      controller.stop();
      controller.dispose();
    });
    controller.openForumTopic('a', 'LV', isVisible: () => true);
    await controller.start('user');
    expect(controller.forumTopicCount('a', 'LV'), 0);
  });

  test('covered or background pages do not clear unread replies', () {
    final controller = InAppBadgeController(_FirestoreStub());
    addTearDown(() {
      controller.stop();
      controller.dispose();
    });
    controller.state.counts['forum/LV/a'] = 2;
    controller.openForumTopic('a', 'LV', isVisible: () => false);
    expect(controller.forumTopicCount('a', 'LV'), 2);
  });

  test(
    'server timestamps ahead of device clock do not resurrect read badges',
    () {
      final controller = InAppBadgeController(_FirestoreStub());
      addTearDown(() {
        controller.stop();
        controller.dispose();
      });
      final serverTime = DateTime.now().millisecondsSinceEpoch + 60000;
      controller.openForumTopic(
        'a',
        'LV',
        isVisible: () => true,
        latestReplyAtMillis: serverTime,
      );
      controller.closeForumTopic('a');
      controller.state.receiveTopic('forum/LV/a', serverTime, own: false);
      expect(controller.forumTopicCount('a', 'LV'), 0);
      controller.state.receiveTopic('forum/LV/a', serverTime + 1, own: false);
      expect(controller.forumTopicCount('a', 'LV'), 1);
    },
  );

  test(
    'forum visits preserve unread; reading a topic clears only that topic',
    () {
      final state = ActivityBadgeState(100);
      state.forumCategories.addAll({
        'forum/LV/a': 'meets_events',
        'forum/LV/b': 'meets_events',
        'forum/LV/c': 'tuning_parts',
        'forum/EE/d': 'meets_events',
      });
      for (final key in state.forumCategories.keys) {
        state.receiveTopic(key, 200, own: false);
      }
      state.receiveTopic('forum/LV/a', 201, own: false);
      state.receiveTopic('forum/LV/a', 202, own: true);
      state.visit(ActivitySection.forum, 300);
      expect(state.forumCount('LV'), 4);
      expect(state.forumCount('LV', category: 'meets_events'), 3);
      expect(state.forumCount('EE'), 1);
      state.readTopic('forum/LV/a', 300);
      expect(state.topicCount('forum/LV/a'), 0);
      expect(state.forumCount('LV'), 2);
      state.receiveTopic('forum/LV/a', 250, own: false);
      expect(state.topicCount('forum/LV/a'), 0);
      state.receiveTopic('forum/LV/a', 301, own: false);
      expect(state.topicCount('forum/LV/a'), 1);
      final restored = ActivityBadgeState.restore(state.toJson(), 400);
      expect(restored.forumCount('LV'), 3);
      expect(restored.topicSeen('forum/LV/a'), 300);
    },
  );

  test('legacy migration replays only forum cursors when unread exists', () {
    final restored = ActivityBadgeState.restore({
      'since': 100,
      'counts': {'forum': 2},
      'seenAt': {'forum': 150},
      'cursors': {
        'forum/LV/a': [1, 0, 'reply'],
        'chat/a': [1, 0, 'message'],
      },
      'summaries': {'forum/LV/a': '1:0', 'chat/a': '1:0'},
    }, 300);
    expect(restored.cursors.containsKey('forum/LV/a'), false);
    expect(restored.cursors.containsKey('chat/a'), true);
    expect(restored.topicSeen('forum/LV/a'), 150);
  });
}
