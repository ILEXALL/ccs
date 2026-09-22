import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show chatMessagesCollection, chatsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent, trySendPushNotificationEvent;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

Future<void> sendChatMessage({
  required String chatId,
  required String text,
  String photoUrl = '',
  ChatThreadData? chat,
  String? messageId,
  int? clientCreatedAtMillis,
  MessageReplyPreviewData? replyTo,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before sending messages.',
    );
  }

  final cleanText = text.trim();
  final cleanPhotoUrl = photoUrl.trim();

  if (cleanText.isEmpty && cleanPhotoUrl.isEmpty) {
    return;
  }

  final cleanMessageId = messageId?.trim() ?? '';
  final messageRef = cleanMessageId.isEmpty
      ? chatMessagesCollection(chatId).doc()
      : chatMessagesCollection(chatId).doc(cleanMessageId);
  final clientMillis =
      clientCreatedAtMillis ?? DateTime.now().millisecondsSinceEpoch;

  final chatMemberIds = chat?.memberIds
      .map((uid) => uid.trim())
      .where((uid) => uid.isNotEmpty)
      .toList();
  final batch = FirebaseFirestore.instance.batch();

  // Commit the message and the chat-list summary together. The receiver's chat
  // list listens to the parent chat document, so writing the message first and
  // updating this summary in a detached Future can leave the new message hidden
  // until another refresh causes the thread to be opened.
  batch.debugSet(
    messageRef,
    {
      'senderUid': firebaseUser.uid,
      'senderUsername': currentUser.username,
      'text': cleanText,
      if (cleanPhotoUrl.isNotEmpty) 'photoUrl': cleanPhotoUrl,
      if (cleanPhotoUrl.isNotEmpty) 'type': 'image',
      'clientCreatedAtMillis': clientMillis,
      'readByUserIds': [firebaseUser.uid],
      if (replyTo != null && replyTo.hasContent) ...{
        'replyToMessageId': replyTo.messageId,
        'replyToUsername': replyTo.username,
        'replyToText': replyTo.text,
        'replyToPhotoUrl': replyTo.photoUrl,
      },
      'createdAt': FieldValue.serverTimestamp(),
    },
    null,
    'chat: send message',
  );
  batch.debugSet(
    chatsCollection().doc(chatId),
    {
      'lastMessage': cleanText.isEmpty ? trText('Photo') : cleanText,
      'lastSenderUid': firebaseUser.uid,
      'lastSenderUsername': currentUser.username,
      if (chatMemberIds != null && chatMemberIds.isNotEmpty)
        'hiddenForUserIds': FieldValue.arrayRemove(chatMemberIds),
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
    'chat: update summary after message send',
  );
  await batch.debugCommit();

  // Do not create a local user_notifications chat row here. The push backend
  // creates the notification-center item for chat messages. Creating a local
  // row plus calling the backend caused duplicated direct-chat notifications.
  try {
    final recipientUserIds =
        chatMemberIds
            ?.where((uid) => uid != firebaseUser.uid)
            .toSet()
            .toList() ??
        const <String>[];

    final pushWasAccepted = await trySendPushNotificationEvent({
      'type': 'chat_message',
      'preferenceKey': 'newMessageNotifications',
      'notificationId': 'chat_${chatId}_${messageRef.id}',
      'chatId': chatId,
      'messageId': messageRef.id,
      'senderUsername': currentUser.username,
      'messageText': cleanText.isEmpty ? trText('Photo') : cleanText,
      if (chat != null) 'isGroup': chat.isGroup,
      if (chat != null) 'chatTitle': chat.titleForCurrentUser(firebaseUser.uid),
      if (recipientUserIds.isNotEmpty) 'recipientUserIds': recipientUserIds,
    });
    if (!pushWasAccepted) {
      debugPrint(
        'Chat push notification was not accepted after message send. '
        'chatId=$chatId messageId=${messageRef.id}',
      );
    }
  } catch (error, stack) {
    // The Firestore batch already delivered the message in-app. A push-service
    // outage must not turn a successful chat send into a failed message.
    debugPrint('Chat push notification skipped after message send: $error');
    debugPrint('$stack');
  }
}

Future<void> markChatMessagesReadByCurrentUser({
  required String chatId,
  required Iterable<ChatMessageData> messages,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return;
  }

  final currentUid = firebaseUser.uid;
  final ids = <String>{};
  final batch = FirebaseFirestore.instance.batch();
  var writeCount = 0;

  for (final message in messages) {
    final messageId = message.id.trim();
    if (messageId.isEmpty ||
        ids.contains(messageId) ||
        message.isLocalPending ||
        message.sendFailed ||
        message.senderUid == currentUid ||
        message.readByUserIds.contains(currentUid)) {
      continue;
    }

    ids.add(messageId);
    batch.debugSet(
      chatMessagesCollection(chatId).doc(messageId),
      {
        'readByUserIds': FieldValue.arrayUnion([currentUid]),
      },
      SetOptions(merge: true),
      'chat: mark message read',
    );
    writeCount++;
  }

  if (writeCount == 0) {
    return;
  }

  await batch.debugCommit();
}

Future<bool> currentUserCanModerateChat(String chatId) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null) return false;

  final snapshot = await chatsCollection().doc(chatId).debugGet();
  final data = snapshot.data();
  if (data == null || data['isGroup'] != true) return false;
  if (currentUserCanModerateCountry(
    stringFromFirebase(data['countryCode'], ''),
    community: true,
  ))
    return true;
  if (currentUser.role == UserRole.moderator) return false;

  final memberIds = stringListFromFirebase(data['memberIds'], const []);
  if (!memberIds.contains(firebaseUser.uid)) return false;

  final ownerUid = stringFromFirebase(
    data['ownerUid'],
    memberIds.isEmpty ? '' : memberIds.first,
  );
  final moderatorIds = stringListFromFirebase(data['moderatorIds'], const []);

  return ownerUid == firebaseUser.uid ||
      moderatorIds.contains(firebaseUser.uid);
}

Future<void> editChatMessage({
  required String chatId,
  required ChatMessageData message,
  required String text,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null || firebaseUser.uid != message.senderUid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can edit only your own messages.',
    );
  }

  final cleanText = text.trim();

  if (cleanText.isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'empty-message',
      message: 'Message cannot be empty.',
    );
  }

  await chatMessagesCollection(chatId).doc(message.id).debugSet({
    'text': cleanText,
    'edited': true,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  unawaited(
    sendPushNotificationEvent({
      'type': 'chat_message',
      'chatId': chatId,
      'messageId': message.id,
      'mentionsOnly': true,
    }),
  );
  try {
    await chatsCollection().doc(chatId).debugSet({
      'lastMessage': cleanText,
      'lastSenderUid': firebaseUser.uid,
      'lastSenderUsername': currentUser.username,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error, stack) {
    debugPrint('Chat summary update skipped after message edit: $error');
    debugPrint('$stack');
  }
}

Future<void> deleteChatMessage({
  required String chatId,
  required ChatMessageData message,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final canModerate = await currentUserCanModerateChat(chatId);

  if (firebaseUser == null ||
      (firebaseUser.uid != message.senderUid && !canModerate)) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'You can delete only your own messages.',
    );
  }

  try {
    // Owners and group moderators should be able to remove messages directly
    // from the group chat. If older Firestore rules reject moderator deletes,
    // fall back to the moderation endpoint used by previous builds.
    await chatMessagesCollection(
      chatId,
    ).doc(message.id).debugDelete('chat: delete message');
  } catch (error) {
    if (firebaseUser.uid == message.senderUid) {
      rethrow;
    }

    await sendModerationAction({
      'action': 'delete_chat_message',
      'chatId': chatId,
      'messageId': message.id,
    });
  }

  final latestSnapshot = await chatMessagesCollection(chatId)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .debugGet(null, 'chat: latest message after delete');
  final latestText = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(latestSnapshot.docs.first.data()['text'], '');
  final latestSenderUid = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(latestSnapshot.docs.first.data()['senderUid'], '');
  final latestSenderUsername = latestSnapshot.docs.isEmpty
      ? ''
      : stringFromFirebase(
          latestSnapshot.docs.first.data()['senderUsername'],
          '',
        );

  try {
    await chatsCollection().doc(chatId).debugSet({
      'lastMessage': latestText,
      'lastSenderUid': latestSenderUid,
      'lastSenderUsername': latestSenderUsername,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (error, stack) {
    debugPrint('Chat summary update skipped after message delete: $error');
    debugPrint('$stack');
  }
}
