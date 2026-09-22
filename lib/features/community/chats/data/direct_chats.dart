import 'package:ccs_app/features/community/chats/models/chat_identity.dart'
    show directChatIdFor;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show chatsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/data/chat_session_cache.dart'
    show chatMessageSessionCache, chatOldestMessageDocSessionCache;
import 'package:ccs_app/features/friends/data/blocked_users.dart'
    show isUserBlockedByCurrentUser;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

Future<String> createOrOpenDirectChat(FriendUserData user) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before opening chat.',
    );
  }

  if (user.uid.trim().isEmpty || user.uid == firebaseUser.uid) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'invalid-chat-user',
      message: 'This user profile is not available anymore.',
    );
  }

  if (await isUserBlockedByCurrentUser(user.uid)) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'blocked-user',
      message: 'You cannot message this user.',
    );
  }

  final chatId = directChatIdFor(firebaseUser.uid, user.uid);
  final memberIds = [firebaseUser.uid, user.uid];
  final memberUsernames = [currentUser.username, user.username];
  final memberPhotoUrls = [currentUser.photoUrl ?? '', user.photoUrl ?? ''];

  final chatRef = chatsCollection().doc(chatId);
  final existingChat = await chatRef.debugGet(
    null,
    'chat: direct open existing chat lookup',
  );

  if (existingChat.exists) {
    // Reopening a chat that this user hid should make it visible again. Avoid
    // refreshing other display fields here; older rules can reject that.
    final hiddenForUserIds = stringListFromFirebase(
      existingChat.data()?['hiddenForUserIds'],
      const [],
    );
    if (hiddenForUserIds.contains(firebaseUser.uid)) {
      try {
        await chatRef.debugSet(
          {
            'hiddenForUserIds': FieldValue.arrayRemove([firebaseUser.uid]),
          },
          SetOptions(merge: true),
          'chat: unhide direct chat on open',
        );
      } catch (error, stack) {
        debugPrint('Direct chat unhide skipped: $error');
        debugPrint('$stack');
      }
    }
    return chatId;
  } else {
    // New direct chats must include the same schema fields that the chat list
    // and Firestore rules expect. Omitting isGroup/lastMessage/createdAt can
    // make the create request fail with permission-denied, which surfaces in
    // the UI as "Could not open chat."
    await chatRef.debugSet({
      'isGroup': false,
      'name': '',
      'memberIds': memberIds,
      'memberUsernames': memberUsernames,
      'memberPhotoUrls': memberPhotoUrls,
      'photoUrl': '',
      'description': '',
      'lastMessage': '',
      'lastSenderUid': '',
      'lastSenderUsername': '',
      'ownerUid': '',
      'moderatorIds': [],
      'hiddenForUserIds': [],
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  return chatId;
}

Future<void> hideChatForCurrentUser(ChatThreadData chat) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? currentUser.uid;
  if (uid.trim().isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before using chat.',
    );
  }

  await chatsCollection()
      .doc(chat.id)
      .debugSet(
        {
          'hiddenForUserIds': FieldValue.arrayUnion([uid]),
        },
        SetOptions(merge: true),
        'chat: hide for current user',
      );
  chatMessageSessionCache.remove(chat.id);
  chatOldestMessageDocSessionCache.remove(chat.id);
}
