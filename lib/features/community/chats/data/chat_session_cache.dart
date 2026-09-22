import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;

final Map<String, List<ChatMessageData>> chatMessageSessionCache = {};

final Map<String, DocumentSnapshot<Map<String, dynamic>>>
chatOldestMessageDocSessionCache = {};
