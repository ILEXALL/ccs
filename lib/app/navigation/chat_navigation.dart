import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/data/direct_chats.dart'
    show createOrOpenDirectChat;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show localizedFriendActionError;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

Future<void> navigateToDirectChat(
  BuildContext context,
  FriendUserData user,
) async {
  try {
    final chatId = await createOrOpenDirectChat(user);
    final chat = ChatThreadData(
      id: chatId,
      isGroup: false,
      name: '',
      memberIds: [currentUser.uid, user.uid],
      memberUsernames: [currentUser.username, user.username],
      memberPhotoUrls: [currentUser.photoUrl ?? '', user.photoUrl ?? ''],
      lastMessage: '',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    if (!context.mounted) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          localizedFriendActionError(error, 'Could not open chat.'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
