import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart'
    show friendshipsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/friends/data/friends_repository.dart'
    show loadCurrentFriendUsers;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class UserAvatarFallback extends StatelessWidget {
  final double size;
  final IconData icon;

  const UserAvatarFallback({super.key, required this.size, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: Icon(icon, color: blue, size: size * 0.5),
    );
  }
}

class UserAvatarCircle extends StatelessWidget {
  final FriendUserData user;
  final double size;

  const UserAvatarCircle({super.key, required this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: blue.withValues(alpha: 0.45)),
      ),
      child: ClipOval(
        child: localFileExists(user.avatarPath)
            ? Image.file(File(user.avatarPath!), fit: BoxFit.cover)
            : isNetworkUrl(user.photoUrl)
            ? Image.network(
                user.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: CcsText(
                    user.username.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : Center(
                child: CcsText(
                  user.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
      ),
    );
  }
}

class OnlineStatusBadge extends StatelessWidget {
  final bool online;
  final double dotSize;
  final double fontSize;

  const OnlineStatusBadge({
    super.key,
    required this.online,
    this.dotSize = 7,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final color = online ? Colors.greenAccent : Colors.white38;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        CcsText(
          online ? 'online' : 'offline',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: online ? Colors.greenAccent : Colors.white54,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

FriendUserData? friendUserFromSnapshot(
  DocumentSnapshot<Map<String, dynamic>>? snapshot,
) {
  if (snapshot == null || !snapshot.exists) {
    return null;
  }

  return FriendUserData.fromFirestore(snapshot);
}

FriendUserData fallbackChatMember(ChatThreadData chat, String uid) {
  final index = chat.memberIds.indexOf(uid);
  final username = index >= 0 && index < chat.memberUsernames.length
      ? chat.memberUsernames[index]
      : 'ccs_driver';
  final photoUrl = index >= 0 && index < chat.memberPhotoUrls.length
      ? chat.memberPhotoUrls[index]
      : '';

  return FriendUserData(
    uid: uid,
    username: username.trim().isEmpty ? 'ccs_driver' : username,
    name: displayUsername(username.trim().isEmpty ? 'ccs_driver' : username),
    email: '',
    photoUrl: photoUrl.trim().isEmpty ? null : photoUrl,
    verified: false,
    role: UserRole.user,
    globalChatModerator: false,
    banned: false,
    deleted: false,
  );
}

List<FriendUserData> chatMembersFromSnapshot(
  QuerySnapshot<Map<String, dynamic>> snapshot,
  ChatThreadData chat,
) {
  final usersById = <String, FriendUserData>{
    for (final doc in snapshot.docs) doc.id: FriendUserData.fromFirestore(doc),
  };

  return [
    for (final uid in chat.memberIds)
      usersById[uid] ?? fallbackChatMember(chat, uid),
  ];
}

Future<List<FriendUserData>> loadChatMembers(ChatThreadData chat) async {
  final members = <FriendUserData>[];

  for (final uid in chat.memberIds) {
    if (uid.trim().isEmpty) {
      continue;
    }

    try {
      final snapshot = await usersCollection().doc(uid).debugGet();
      members.add(
        snapshot.exists
            ? FriendUserData.fromFirestore(snapshot)
            : fallbackChatMember(chat, uid),
      );
    } catch (_) {
      members.add(fallbackChatMember(chat, uid));
    }
  }

  return members;
}

Stream<List<FriendUserData>> watchCurrentFriendUsers() {
  final firebaseUser = FirebaseAuth.instance.currentUser;

  if (firebaseUser == null) {
    return Stream.value(const <FriendUserData>[]);
  }

  return friendshipsCollection()
      .where('userIds', arrayContains: firebaseUser.uid)
      .debugSnapshots('friends: current friendships listener')
      .asyncMap((_) => loadCurrentFriendUsers());
}

FriendUserData fallbackMessageSender(ChatMessageData message) {
  final username = message.senderUsername.trim().isEmpty
      ? 'ccs_driver'
      : message.senderUsername;

  return FriendUserData(
    uid: message.senderUid,
    username: username,
    name: displayUsername(username),
    email: '',
    verified: false,
    role: UserRole.user,
    globalChatModerator: false,
    banned: false,
    deleted: false,
  );
}
