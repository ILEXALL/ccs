import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/firestore/collections.dart' show chatsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserHomeCountryCode;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/data/chat_session_cache.dart'
    show chatMessageSessionCache, chatOldestMessageDocSessionCache;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/shared/media/entity_photos.dart'
    show uploadGroupAvatarPhoto;

String groupVisibilityLabel(bool isPrivate) => isPrivate
    ? communityText(
        en: 'Private group',
        ru: 'Закрытая группа',
        lv: 'Privāta grupa',
      )
    : communityText(
        en: 'Public group',
        ru: 'Открытая группа',
        lv: 'Publiska grupa',
      );

String groupMemberCountLabel(int count) =>
    communityText(en: 'Members: ', ru: 'Участников: ', lv: 'Dalībnieki: ') +
    count.toString();

Future<String> createGroupChat({
  required String name,
  required String description,
  required List<FriendUserData> users,
  String? avatarLocalPath,
  bool isPrivate = false,
}) async {
  if (description.trim().isEmpty || description.trim().length > 1000)
    throw ArgumentError('Enter a group description (1–1000 characters).');
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before creating chat.',
    );
  }

  final uniqueUsers = <String, FriendUserData>{
    for (final user in users) user.uid: user,
  }.values.toList();
  final memberIds = [firebaseUser.uid, ...uniqueUsers.map((user) => user.uid)];
  final memberUsernames = [
    currentUser.username,
    ...uniqueUsers.map((user) => user.username),
  ];
  final fallbackName = uniqueUsers
      .map((user) => user.username)
      .where((username) => username.trim().isNotEmpty)
      .take(3)
      .join(', ');
  final doc = chatsCollection().doc();
  final cleanAvatarLocalPath = avatarLocalPath?.trim() ?? '';
  final groupAvatarUrl = cleanAvatarLocalPath.isEmpty
      ? ''
      : await uploadGroupAvatarPhoto(
          groupId: doc.id,
          localPhotoPath: cleanAvatarLocalPath,
        );

  await doc.debugSet({
    'isGroup': true,
    'countryCode': currentUserHomeCountryCode(),
    'name': name.trim().isEmpty ? fallbackName : name.trim(),
    'memberIds': memberIds,
    'memberUsernames': memberUsernames,
    'memberPhotoUrls': [
      currentUser.photoUrl ?? '',
      ...uniqueUsers.map((user) => user.photoUrl ?? ''),
    ],
    'ownerUid': firebaseUser.uid,
    'moderatorIds': [],
    'isPrivate': isPrivate,
    'photoUrl': groupAvatarUrl,
    'avatarUrl': groupAvatarUrl,
    'description': description.trim(),
    'lastMessage': '',
    'lastSenderUid': '',
    'lastSenderUsername': '',
    'hiddenForUserIds': [],
    'updatedAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  unawaited(
    sendPushNotificationEvent({
      'type': 'group_members_added',
      'chatId': doc.id,
    }),
  );
  return doc.id;
}

Future<void> deleteGroupChat(ChatThreadData chat) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final uid = firebaseUser?.uid ?? currentUser.uid;
  final canDelete =
      chat.isGroup &&
      (chat.isOwner(uid) ||
          currentUserCanModerateCountry(chat.countryCode, community: true));

  if (!canDelete) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: trText('Only the group owner can delete this group.'),
    );
  }

  await chatsCollection().doc(chat.id).debugDelete('chat: delete group');
  chatMessageSessionCache.remove(chat.id);
  chatOldestMessageDocSessionCache.remove(chat.id);
}

Future<void> leaveGroupChat(ChatThreadData chat) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  if (firebaseUser == null || firebaseUser.uid.trim().isEmpty) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'not-logged-in',
      message: 'Log in before using chat.',
    );
  }

  final uid = firebaseUser.uid.trim();
  final chatRef = chatsCollection().doc(chat.id);

  // Rebuild the parallel member arrays by index instead of arrayRemove().
  // Usernames and photo URLs are not unique: several members can have the
  // same value (especially an empty photo URL). arrayRemove() would remove
  // every matching value, corrupting the parallel arrays and causing schema
  // validation in Firestore rules to reject the leave operation.
  await FirebaseFirestore.instance.debugRunTransaction((transaction) async {
    final snapshot = await transaction.debugGet(
      chatRef,
      'chat: leave group server verify',
    );

    if (!snapshot.exists) {
      return;
    }

    final latestChat = ChatThreadData.fromFirestore(snapshot);
    if (!latestChat.isGroup || !latestChat.memberIds.contains(uid)) {
      return;
    }

    final leavingOwner = latestChat.isOwner(uid);
    if (latestChat.memberIds.length <= 1) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'last-member-cannot-leave',
        message: trText('You are the only member. Delete the group instead.'),
      );
    }

    final nextMemberIds = [...latestChat.memberIds];
    final nextMemberUsernames = [...latestChat.memberUsernames];
    final nextMemberPhotoUrls = [...latestChat.memberPhotoUrls];
    final nextModeratorIds = [...latestChat.moderatorIds];

    final memberIndex = nextMemberIds.indexOf(uid);
    if (memberIndex < 0) {
      return;
    }

    nextMemberIds.removeAt(memberIndex);
    if (memberIndex < nextMemberUsernames.length) {
      nextMemberUsernames.removeAt(memberIndex);
    }
    if (memberIndex < nextMemberPhotoUrls.length) {
      nextMemberPhotoUrls.removeAt(memberIndex);
    }
    nextModeratorIds.removeWhere((memberUid) => memberUid == uid);

    final nextOwnerUid = leavingOwner
        ? nextModeratorIds.firstWhere(
            nextMemberIds.contains,
            orElse: () => nextMemberIds.first,
          )
        : latestChat.effectiveOwnerUid();

    transaction.debugUpdate(chatRef, {
      'ownerUid': nextOwnerUid,
      'memberIds': nextMemberIds,
      'memberUsernames': nextMemberUsernames,
      'memberPhotoUrls': nextMemberPhotoUrls,
      'moderatorIds': nextModeratorIds,
      'hiddenForUserIds': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, 'chat: leave group');
  });

  chatMessageSessionCache.remove(chat.id);
  chatOldestMessageDocSessionCache.remove(chat.id);
}
