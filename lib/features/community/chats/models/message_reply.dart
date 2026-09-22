import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;

class MessageReplyPreviewData {
  final String messageId;
  final String username;
  final String text;
  final String photoUrl;

  const MessageReplyPreviewData({
    required this.messageId,
    required this.username,
    required this.text,
    required this.photoUrl,
  });

  bool get hasContent =>
      messageId.trim().isNotEmpty ||
      username.trim().isNotEmpty ||
      text.trim().isNotEmpty ||
      photoUrl.trim().isNotEmpty;
}

Map<String, String> messageReactionsFromFirebase(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }

  final reactions = <String, String>{};
  for (final entry in value.entries) {
    final uid = entry.key.toString().trim();
    final emoji = entry.value?.toString().trim() ?? '';
    if (uid.isNotEmpty && emoji.isNotEmpty) {
      reactions[uid] = emoji;
    }
  }
  return reactions;
}

MessageReplyPreviewData messageReplyPreviewFromFirebase(
  Map<String, dynamic> data,
) {
  return MessageReplyPreviewData(
    messageId: stringFromFirebase(data['replyToMessageId'], ''),
    username: stringFromFirebase(data['replyToUsername'], ''),
    text: stringFromFirebase(data['replyToText'], ''),
    photoUrl: stringFromFirebase(data['replyToPhotoUrl'], ''),
  );
}
