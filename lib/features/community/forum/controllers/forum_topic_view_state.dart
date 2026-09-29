import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;

abstract interface class ForumTopicInputs {
  String get topicId;
  String get title;
  String get countryCode;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class ForumTopicViewState {
  BuildContext get context;
  bool get mounted;
  ForumTopicInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get replyController;
  FocusNode get replyFocusNode;
  ScrollController get topicScrollController;
  Stream<DocumentSnapshot<Map<String, dynamic>>> get stateTopicStream;
  Stream<QuerySnapshot<Map<String, dynamic>>> get stateRepliesStream;
  bool get isSending;
  set isSending(bool value);
  bool get isUploadingPhotoAttachment;
  set isUploadingPhotoAttachment(bool value);
  String? get pendingPhotoAttachmentPath;
  set pendingPhotoAttachmentPath(String? value);
  QueryDocumentSnapshot<Map<String, dynamic>>? get replyingToForumReply;
  set replyingToForumReply(QueryDocumentSnapshot<Map<String, dynamic>>? value);
  String get stateTopicCountryCode;
  set stateTopicCountryCode(String value);
  bool get stateTopicCountryResolved;
  set stateTopicCountryResolved(bool value);
  bool get stateHasLoadedReplies;
  set stateHasLoadedReplies(bool value);
  int? get stateLatestLoadedReplyAtMillis;
  set stateLatestLoadedReplyAtMillis(int? value);
  Map<String, dynamic>? get stateResolvedTopic;
  set stateResolvedTopic(Map<String, dynamic>? value);
  ForumTopicContentActions get content;
  ForumTopicControllerActions get controller;
}

abstract interface class ForumTopicContentActions {
  Widget topicHeader(Map<String, dynamic> topic);
  Widget replyTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool showAuthorHeader,
  });
}

abstract interface class ForumTopicControllerActions {
  bool get isReadingTopic;
  void markLoadedRepliesRead(String countryCode);
  DocumentReference<Map<String, dynamic>> get topicDocument;
  CollectionReference<Map<String, dynamic>> get topicRepliesCollection;
  bool get canModerateForumTopic;
  void groupMembershipChanged();
  bool get canPostInForumTopic;
  Future<void> loadCommunityModerationAccess();
  Future<void> attachPhoto({bool useCamera = false});
  Future<void> sendReply();
  Future<void> toggleTopicPinned(bool isPinned);
  Future<void> editTopicHeader(Map<String, dynamic> topic);
  Future<void> deleteTopic();
  Future<void> confirmDeleteForumReply(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
  Future<void> reactToForumReply(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    String? preferredEmoji,
  });
  Future<void> showForumReplyActions(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
  Future<void> showEditForumReplyDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  );
}
