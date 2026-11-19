import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/spots/models/spot_review.dart';
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart';

void main() {
  test(
    'legacy review has no reactions; persisted entries survive decoding',
    () {
      expect(SpotReviewData.fromData('review', {}).reactions, isEmpty);
      expect(
        SpotReviewData.fromData('review', {
          'reactions': {'alice': '❤️', 'bob': '🔥'},
        }).reactions,
        {'alice': '❤️', 'bob': '🔥'},
      );
    },
  );
  testWidgets(
    'shared comment picker selects and removes reactions; badges aggregate users',
    (tester) async {
      String? selected;
      String? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      selected = await showEmojiReactionPicker(
                        context,
                        currentEmoji: '❤️',
                      );
                    },
                    child: const Text('React'),
                  ),
                  messageReactionBar(
                    reactions: {'a': '❤️', 'b': '❤️', 'c': '🔥'},
                    currentUid: 'a',
                    onEmojiTap: (emoji) => tapped = emoji,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('❤️ 2'), findsOneWidget);
      await tester.tap(find.text('🔥 1'));
      expect(tapped, '🔥');
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();
      expect(selected, '👍');
      await tester.tap(find.text('React'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove reaction'));
      await tester.pumpAndSettle();
      expect(selected, '');
    },
  );
}
