import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/in_app_badges.dart';

void main() {
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
