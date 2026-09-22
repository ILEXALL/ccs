import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;

abstract interface class GlobalChatInputs {
  bool get isActive;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class GlobalChatViewState {
  BuildContext get context;
  bool get mounted;
  GlobalChatInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get messageController;
  FocusNode get messageFocusNode;
  ScrollController get globalChatScrollController;
  Stream<QuerySnapshot<Map<String, dynamic>>>? get onlineUsersStream;
  set onlineUsersStream(Stream<QuerySnapshot<Map<String, dynamic>>>? value);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get stateGlobalMessagesSubscription;
  set stateGlobalMessagesSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get stateGlobalMessages;
  DocumentSnapshot<Map<String, dynamic>>? get stateOldestLoadedGlobalMessageDoc;
  set stateOldestLoadedGlobalMessageDoc(
    DocumentSnapshot<Map<String, dynamic>>? value,
  );
  bool get stateIsInitialLoadingGlobalMessages;
  set stateIsInitialLoadingGlobalMessages(bool value);
  bool get stateIsLoadingOlderGlobalMessages;
  set stateIsLoadingOlderGlobalMessages(bool value);
  bool get stateHasMoreOlderGlobalMessages;
  set stateHasMoreOlderGlobalMessages(bool value);
  bool get stateGlobalPaginationInitialized;
  set stateGlobalPaginationInitialized(bool value);
  bool get stateScrollGlobalChatToLatestAfterSend;
  set stateScrollGlobalChatToLatestAfterSend(bool value);
  bool get stateGlobalMessagesLoadFailed;
  set stateGlobalMessagesLoadFailed(bool value);
  bool get stateLegacyLatvianMessagesLoaded;
  set stateLegacyLatvianMessagesLoaded(bool value);
  bool get isSending;
  set isSending(bool value);
  bool get isUploadingPhotoAttachment;
  set isUploadingPhotoAttachment(bool value);
  String? get pendingPhotoAttachmentPath;
  set pendingPhotoAttachmentPath(String? value);
  QueryDocumentSnapshot<Map<String, dynamic>>? get replyingToGlobalMessage;
  set replyingToGlobalMessage(
    QueryDocumentSnapshot<Map<String, dynamic>>? value,
  );
  int? get stateLastGlobalChatMessageSentAtMillis;
  set stateLastGlobalChatMessageSentAtMillis(int? value);
  GlobalChatContentActions get content;
  GlobalChatControllerActions get controller;
}

abstract interface class GlobalChatContentActions {
  Widget messageBubble(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool showAuthorHeader,
  });
}

abstract interface class GlobalChatControllerActions {
  void updateOnlineUsersStream();
  void handleLanguageChanged();
  CollectionReference<Map<String, dynamic>> get globalChatCollection;
  String get selectedCommunityCountryCode;
  bool get canPostInSelectedCommunity;
  int get activeGlobalChatQueryPageSize;
  Query<Map<String, dynamic>> get latestGlobalChatMessagesQuery;
  bool get canModerateGlobalChat;
  Future<void> loadGlobalChatModeratorAccess();
  void handleCommunityCountryChanged();
  bool globalMessageHasContent(QueryDocumentSnapshot<Map<String, dynamic>> doc);
  void mergeGlobalMessages(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> incoming,
  );
  void startGlobalMessagesListener({bool useUnindexedFallback = false});
  Future<void> loadLegacyLatvianGlobalMessages();
  void onGlobalChatScroll();
  Future<void> loadOlderGlobalMessages();
  bool isNearLatestGlobalMessage();
  void scheduleGlobalChatScrollToLatest();
  Future<void> confirmDeleteGlobalMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
  Future<void> reactToGlobalMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    String? preferredEmoji,
  });
  Future<void> showGlobalMessageActions(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
  Future<void> showEditGlobalMessageDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
  Future<void> attachPhoto();
  Duration localGlobalChatSendCooldownRemaining();
  void showGlobalChatSpamWarning(Duration remaining);
  Future<int> writeGlobalChatMessageWithCooldown({
    required User firebaseUser,
    required DocumentReference<Map<String, dynamic>> messageDoc,
    required String text,
    required String photoUrl,
    MessageReplyPreviewData? replyTo,
  });
  Future<void> sendMessage();
  List<Widget> globalChatMessageList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  );
}
