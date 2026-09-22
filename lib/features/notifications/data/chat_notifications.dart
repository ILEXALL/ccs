import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/notifications/data/user_notifications.dart'
    show createUserNotification;

Future<void> createChatMessageNotification({
  required ChatThreadData chat,
  required String messageText,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) {
    return;
  }

  final recipients = chat.memberIds
      .where((uid) => uid.trim().isNotEmpty && uid != firebaseUser.uid)
      .toSet();
  for (final userId in recipients) {
    await createUserNotification(
      userId: userId,
      type: 'chat_message',
      title: 'Messages',
      body: chat.isGroup
          ? '@${currentUser.username} in ${chat.titleForCurrentUser(userId)}: $messageText'
          : '@${currentUser.username}: $messageText',
      settingName: 'newMessageNotifications',
      notificationId:
          'chat_${chat.id}_${DateTime.now().microsecondsSinceEpoch}_$userId',
      extra: {
        'chatId': chat.id,
        'isGroup': chat.isGroup,
        'senderUid': firebaseUser.uid,
        'senderUsername': currentUser.username,
        'chatTitle': chat.titleForCurrentUser(userId),
      },
    );
  }
}
