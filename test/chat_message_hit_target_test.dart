import 'package:ccs_app/features/community/chats/models/chat_thread.dart';
import 'package:ccs_app/features/community/chats/widgets/message_bubble_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/community/chats/controllers/chat_conversation_view_state.dart';
import 'package:ccs_app/features/community/chats/models/chat_message.dart';
import 'package:ccs_app/features/community/chats/widgets/chat_conversation_content.dart';

class Actions implements ChatConversationControllerActions {
  int opened = 0;
  @override
  bool get readOnly => false;
  @override
  Future<void> showOwnMessageActions(ChatMessageData message) async {
    opened++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Inputs implements ChatConversationInputs {
  @override
  bool get readOnly => false;
  @override
  final chat = const ChatThreadData(
    id: 'chat',
    isGroup: true,
    name: 'Test',
    memberIds: ['viewer', 'other'],
    memberUsernames: ['viewer', 'other'],
    lastMessage: '',
    updatedAtMillis: 1,
  );
}

class Host implements ChatConversationViewState {
  @override
  late BuildContext context;
  @override
  final Actions controller = Actions();
  @override
  final widget = Inputs();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final text in [
    'x',
    'own',
    'reply',
    'https://example.com',
    'A longer message that wraps over several lines in the conversation.',
  ]) {
    testWidgets(
      'hold entire bubble for actions without a three-dot menu: $text',
      (tester) async {
        final host = Host();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  host.context = context;
                  return ChatConversationContent(host).messageBubble(
                    ChatMessageData(
                      id: 'm',
                      senderUid: text == 'own' ? 'viewer' : 'other',
                      replyToMessageId: text == 'reply' ? 'previous' : '',
                      replyToUsername: text == 'reply' ? 'driver' : '',
                      replyToText: text == 'reply' ? 'Previous message' : '',
                      senderUsername: 'driver',
                      text: text,
                      createdAtMillis: 1,
                    ),
                    'viewer',
                    {},
                    showAuthorHeader: false,
                  );
                },
              ),
            ),
          ),
        );
        expect(find.byIcon(Icons.more_horiz), findsNothing);
        final bubble = find.byType(MessageBubbleActions);
        expect(tester.getSize(bubble).height, greaterThanOrEqualTo(48));
        // Plain bubble tap must not open actions; preserve normal link taps.
        await tester.tapAt(tester.getBottomRight(bubble) - const Offset(4, 4));
        expect(host.controller.opened, 0);
        await tester.longPressAt(
          tester.getTopLeft(bubble) + const Offset(15, 15),
        );
        expect(host.controller.opened, 1);
        await tester.longPressAt(
          tester.getBottomRight(bubble) - const Offset(4, 4),
        );
        expect(host.controller.opened, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'child media taps survive, holds open menu and scrolling cancels holds',
    (tester) async {
      var taps = 0, holds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MessageBubbleActions(
                  onLongPress: () => holds++,
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: Container(
                      height: 120,
                      color: Colors.blue,
                      child: const Text('media'),
                    ),
                  ),
                ),
                const SizedBox(height: 1500),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('media'));
      expect(taps, 1);
      expect(holds, 0);
      await tester.longPress(find.text('media'));
      expect(taps, 1);
      expect(holds, 1);
      await tester.drag(find.text('media'), const Offset(0, -90));
      await tester.pump(const Duration(seconds: 1));
      expect(holds, 1);
    },
  );
}
