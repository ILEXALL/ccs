import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show chatMessagesCollection, chatsCollection;

const int firebaseChatsListenLimit = 60;

const int firebaseChatMessagesListenLimit = 10;

Query<Map<String, dynamic>> currentUserChatsQuery(String uid) {
  return chatsCollection()
      .where('memberIds', arrayContains: uid)
      .limit(firebaseChatsListenLimit);
}

Query<Map<String, dynamic>> latestChatMessagesQuery(String chatId) {
  return chatMessagesCollection(chatId)
      .orderBy('createdAt', descending: true)
      .limit(firebaseChatMessagesListenLimit);
}
