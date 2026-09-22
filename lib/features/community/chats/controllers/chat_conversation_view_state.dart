import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

abstract interface class ChatConversationInputs {
  ChatThreadData get chat;
  bool get readOnly;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class ChatConversationViewState {
  BuildContext get context;
  bool get mounted;
  ChatConversationInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get messageController;
  FocusNode get messageFocusNode;
  ScrollController get chatScrollController;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get stateNewMessagesSubscription;
  set stateNewMessagesSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  Future<List<FriendUserData>>? get stateChatMembersFuture;
  set stateChatMembersFuture(Future<List<FriendUserData>>? value);
  Timer? get stateMarkMessagesReadDebounce;
  set stateMarkMessagesReadDebounce(Timer? value);
  bool get isSharingChatLocation;
  set isSharingChatLocation(bool value);
  bool get isUploadingPhotoAttachment;
  set isUploadingPhotoAttachment(bool value);
  String? get pendingPhotoAttachmentPath;
  set pendingPhotoAttachmentPath(String? value);
  ChatMessageData? get replyingToMessage;
  set replyingToMessage(ChatMessageData? value);
  bool get hasScrolledToLatestMessage;
  set hasScrolledToLatestMessage(bool value);
  bool get scrollToLatestAfterNextMessage;
  set scrollToLatestAfterNextMessage(bool value);
  int get renderedMessageCount;
  set renderedMessageCount(int value);
  Set<String> get stateLocallyReadMessageIds;
  List<ChatMessageData> get stateMessages;
  DocumentSnapshot<Map<String, dynamic>>? get stateOldestLoadedDoc;
  set stateOldestLoadedDoc(DocumentSnapshot<Map<String, dynamic>>? value);
  bool get stateIsInitialLoadingMessages;
  set stateIsInitialLoadingMessages(bool value);
  bool get stateIsLoadingOlderMessages;
  set stateIsLoadingOlderMessages(bool value);
  bool get stateHasMoreOlderMessages;
  set stateHasMoreOlderMessages(bool value);
  bool get statePaginationInitialized;
  set statePaginationInitialized(bool value);
  ChatConversationContentActions get content;
  ChatConversationControllerActions get controller;
}

abstract interface class ChatConversationContentActions {
  Widget directChatTitle(
    String currentUid,
    String fallbackTitle,
    String fallbackPhotoUrl,
  );
  Widget groupChatTitle(String title);
  Widget messageBubble(
    ChatMessageData message,
    String currentUid,
    Map<String, FriendUserData> usersById, {
    required bool showAuthorHeader,
  });
}

abstract interface class ChatConversationControllerActions {
  bool get readOnly;
  void cacheMessages();
  void markCurrentChatNotificationsRead({Duration delay = Duration.zero});
  void scheduleMarkVisibleMessagesRead({
    Duration delay = const Duration(milliseconds: 650),
  });
  Future<void> markVisibleMessagesRead();
  void mergeMessages(Iterable<ChatMessageData> incoming);
  void updateMessage(
    String messageId,
    ChatMessageData Function(ChatMessageData message) update,
  );
  Future<void> loadInitialMessages();
  void startNewMessagesListener();
  void onScroll();
  Future<void> loadOlderMessages();
  bool isNearLatestMessage();
  void scheduleScrollToLatestMessage();
  void updateChatScrollForMessages(int messageCount);
  Future<void> attachPhoto();
  Future<void> sendMessage();
  Future<void> shareLiveLocation();
  String? otherUserId(String currentUid);
  String otherUsername(String currentUid);
  void openChatUserProfile(String currentUid);
  Future<void> openGroupSettings();
  Future<void> removeCurrentChat();
  Future<void> reactToChatMessage(
    ChatMessageData message, {
    String? preferredEmoji,
  });
  Future<void> showOwnMessageActions(ChatMessageData message);
  Future<void> deleteMessageImmediately(ChatMessageData message);
  Future<void> showEditMessageDialog(ChatMessageData message);
  Future<void> confirmDeleteMessage(ChatMessageData message);
}
