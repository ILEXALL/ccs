import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        intFromFirebase,
        stringFromFirebase,
        stringListFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData, messageReactionsFromFirebase;

enum ChatMessageReceiptState { sending, delivered, read, failed }

class ChatMessageData {
  final String id;
  final String senderUid;
  final String senderUsername;
  final String text;
  final String photoUrl;
  final int createdAtMillis;
  final bool edited;
  final int updatedAtMillis;
  final int clientCreatedAtMillis;
  final List<String> readByUserIds;
  final bool isLocalPending;
  final bool sendFailed;
  final String replyToMessageId;
  final String replyToUsername;
  final String replyToText;
  final String replyToPhotoUrl;
  final Map<String, String> reactions;

  const ChatMessageData({
    required this.id,
    required this.senderUid,
    required this.senderUsername,
    required this.text,
    this.photoUrl = '',
    required this.createdAtMillis,
    this.edited = false,
    this.updatedAtMillis = 0,
    this.clientCreatedAtMillis = 0,
    this.readByUserIds = const [],
    this.isLocalPending = false,
    this.sendFailed = false,
    this.replyToMessageId = '',
    this.replyToUsername = '',
    this.replyToText = '',
    this.replyToPhotoUrl = '',
    this.reactions = const <String, String>{},
  });

  factory ChatMessageData.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final clientCreatedAtMillis = intFromFirebase(
      data['clientCreatedAtMillis'],
      0,
    );
    final createdAtMillis = timestampMillisFromFirebase(data['createdAt']);

    return ChatMessageData(
      id: doc.id,
      senderUid: stringFromFirebase(data['senderUid'], ''),
      senderUsername: stringFromFirebase(data['senderUsername'], 'ccs_driver'),
      text: stringFromFirebase(data['text'], ''),
      photoUrl: stringFromFirebase(
        data['photoUrl'],
        stringFromFirebase(data['imageUrl'], ''),
      ),
      createdAtMillis: createdAtMillis > 0
          ? createdAtMillis
          : clientCreatedAtMillis,
      edited: data['edited'] == true,
      updatedAtMillis: timestampMillisFromFirebase(data['updatedAt']),
      clientCreatedAtMillis: clientCreatedAtMillis,
      readByUserIds: stringListFromFirebase(data['readByUserIds'], const []),
      isLocalPending: doc.metadata.hasPendingWrites,
      replyToMessageId: stringFromFirebase(data['replyToMessageId'], ''),
      replyToUsername: stringFromFirebase(data['replyToUsername'], ''),
      replyToText: stringFromFirebase(data['replyToText'], ''),
      replyToPhotoUrl: stringFromFirebase(data['replyToPhotoUrl'], ''),
      reactions: messageReactionsFromFirebase(data['reactions']),
    );
  }

  factory ChatMessageData.pending({
    required String id,
    required String senderUid,
    required String senderUsername,
    required String text,
    String photoUrl = '',
    required int createdAtMillis,
    MessageReplyPreviewData? replyTo,
  }) {
    return ChatMessageData(
      id: id,
      senderUid: senderUid,
      senderUsername: senderUsername,
      text: text,
      photoUrl: photoUrl,
      createdAtMillis: createdAtMillis,
      clientCreatedAtMillis: createdAtMillis,
      readByUserIds: [senderUid],
      isLocalPending: true,
      replyToMessageId: replyTo?.messageId ?? '',
      replyToUsername: replyTo?.username ?? '',
      replyToText: replyTo?.text ?? '',
      replyToPhotoUrl: replyTo?.photoUrl ?? '',
    );
  }

  MessageReplyPreviewData get replyPreview => MessageReplyPreviewData(
    messageId: replyToMessageId,
    username: replyToUsername,
    text: replyToText,
    photoUrl: replyToPhotoUrl,
  );

  ChatMessageData copyWith({
    String? id,
    String? senderUid,
    String? senderUsername,
    String? text,
    String? photoUrl,
    int? createdAtMillis,
    bool? edited,
    int? updatedAtMillis,
    int? clientCreatedAtMillis,
    List<String>? readByUserIds,
    bool? isLocalPending,
    bool? sendFailed,
    String? replyToMessageId,
    String? replyToUsername,
    String? replyToText,
    String? replyToPhotoUrl,
    Map<String, String>? reactions,
  }) {
    return ChatMessageData(
      id: id ?? this.id,
      senderUid: senderUid ?? this.senderUid,
      senderUsername: senderUsername ?? this.senderUsername,
      text: text ?? this.text,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAtMillis: createdAtMillis ?? this.createdAtMillis,
      edited: edited ?? this.edited,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      clientCreatedAtMillis:
          clientCreatedAtMillis ?? this.clientCreatedAtMillis,
      readByUserIds: readByUserIds ?? this.readByUserIds,
      isLocalPending: isLocalPending ?? this.isLocalPending,
      sendFailed: sendFailed ?? this.sendFailed,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToUsername: replyToUsername ?? this.replyToUsername,
      replyToText: replyToText ?? this.replyToText,
      replyToPhotoUrl: replyToPhotoUrl ?? this.replyToPhotoUrl,
      reactions: reactions ?? this.reactions,
    );
  }

  ChatMessageReceiptState receiptStateFor(
    ChatThreadData chat,
    String currentUid,
  ) {
    if (sendFailed) {
      return ChatMessageReceiptState.failed;
    }
    if (isLocalPending) {
      return ChatMessageReceiptState.sending;
    }

    final readBy = readByUserIds.map((uid) => uid.trim()).toSet();
    final recipients = chat.memberIds
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty && uid != currentUid)
        .toSet();

    if (recipients.isNotEmpty &&
        recipients.every((uid) => readBy.contains(uid))) {
      return ChatMessageReceiptState.read;
    }

    return ChatMessageReceiptState.delivered;
  }
}
