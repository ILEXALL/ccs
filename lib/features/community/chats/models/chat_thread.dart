import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;

class ChatThreadData {
  final String id;
  final String countryCode;
  final bool isGroup;
  final String name;
  final String photoUrl;
  final String description;
  final List<String> memberIds;
  final List<String> memberUsernames;
  final List<String> memberPhotoUrls;
  final String lastMessage;
  final String lastSenderUid;
  final String lastSenderUsername;
  final String avatarUrl;
  final String ownerUid;
  final List<String> moderatorIds;
  final bool isPrivate;
  final List<String> hiddenForUserIds;
  final int updatedAtMillis;

  const ChatThreadData({
    required this.id,
    this.countryCode = '',
    required this.isGroup,
    required this.name,
    this.photoUrl = '',
    this.description = '',
    required this.memberIds,
    required this.memberUsernames,
    this.memberPhotoUrls = const [],
    required this.lastMessage,
    this.lastSenderUid = '',
    this.lastSenderUsername = '',
    this.avatarUrl = '',
    this.ownerUid = '',
    this.moderatorIds = const [],
    this.isPrivate = false,
    this.hiddenForUserIds = const [],
    required this.updatedAtMillis,
  });

  factory ChatThreadData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};

    return ChatThreadData(
      id: doc.id,
      countryCode: stringFromFirebase(data['countryCode'], ''),
      isGroup: data['isGroup'] == true,
      name: stringFromFirebase(data['name'], ''),
      photoUrl: stringFromFirebase(data['photoUrl'], ''),
      description: stringFromFirebase(data['description'], ''),
      memberIds: stringListFromFirebase(data['memberIds'], const []),
      memberUsernames: stringListFromFirebase(
        data['memberUsernames'],
        const [],
      ),
      memberPhotoUrls: stringListFromFirebase(
        data['memberPhotoUrls'],
        const [],
      ),
      lastMessage: stringFromFirebase(data['lastMessage'], ''),
      lastSenderUid: stringFromFirebase(data['lastSenderUid'], ''),
      lastSenderUsername: stringFromFirebase(data['lastSenderUsername'], ''),
      avatarUrl: stringFromFirebase(data['avatarUrl'], ''),
      ownerUid: stringFromFirebase(data['ownerUid'], ''),
      moderatorIds: stringListFromFirebase(data['moderatorIds'], const []),
      isPrivate: data['isPrivate'] == true,
      hiddenForUserIds: stringListFromFirebase(
        data['hiddenForUserIds'],
        const [],
      ),
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
    );
  }

  String effectiveOwnerUid() {
    if (ownerUid.trim().isNotEmpty) {
      return ownerUid.trim();
    }

    return memberIds.isEmpty ? '' : memberIds.first;
  }

  bool isOwner(String uid) {
    return uid.trim().isNotEmpty && effectiveOwnerUid() == uid.trim();
  }

  bool isHiddenFor(String uid) {
    return hiddenForUserIds.contains(uid.trim());
  }

  String titleForCurrentUser(String currentUid) {
    if (isGroup) {
      return name.trim().isEmpty ? 'Group chat' : name.trim();
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberUsernames.length &&
          memberUsernames[index].trim().isNotEmpty) {
        return displayUsername(memberUsernames[index]);
      }

      return 'Direct chat';
    }

    return 'Direct chat';
  }

  String subtitleForCurrentUser(String currentUid) {
    if (lastMessage.trim().isNotEmpty) {
      if (isGroup) {
        if (lastSenderUid.trim().isEmpty && lastSenderUsername.trim().isEmpty) {
          return lastMessage.trim();
        }

        final sender = lastSenderUid == currentUid
            ? 'You'
            : displayUsername(
                lastSenderUsername.trim().isEmpty
                    ? 'ccs_driver'
                    : lastSenderUsername,
              );
        return '$sender: ${lastMessage.trim()}';
      }

      return lastMessage.trim();
    }

    if (isGroup) {
      return description.trim().isNotEmpty
          ? description.trim()
          : '${memberIds.length} members';
    }

    return 'No messages yet';
  }

  String directPhotoUrlForCurrentUser(String currentUid) {
    if (isGroup) {
      return photoUrl.trim().isNotEmpty ? photoUrl : avatarUrl;
    }

    for (var index = 0; index < memberIds.length; index++) {
      if (memberIds[index] == currentUid) {
        continue;
      }

      if (index < memberPhotoUrls.length) {
        return memberPhotoUrls[index];
      }
    }

    return '';
  }
}
