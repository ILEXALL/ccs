import 'package:ccs_app/features/community/chats/controllers/chat_conversation_view_state.dart';
import 'package:ccs_app/features/community/chats/widgets/chat_conversation_content.dart';
import 'package:ccs_app/features/community/chats/controllers/chat_conversation_controller.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show stagedChatPhotoPreview;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show chatRemovalButtonLabel, currentUserCanDeleteGroupChat;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show chatDateDivider, chatDateDividerLabel;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show messageReplyPreviewCard;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show fallbackChatMember, loadChatMembers;

class ChatConversationScreen extends StatefulWidget
    implements ChatConversationInputs {
  @override
  final ChatThreadData chat;

  @override
  final bool readOnly;

  const ChatConversationScreen({
    super.key,
    required this.chat,
    this.readOnly = false,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen>
    with LanguageReactiveState
    implements ChatConversationViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get stateNewMessagesSubscription => _newMessagesSubscription;

  @override
  set stateNewMessagesSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  ) => _newMessagesSubscription = value;

  @override
  Future<List<FriendUserData>>? get stateChatMembersFuture =>
      _chatMembersFuture;

  @override
  set stateChatMembersFuture(Future<List<FriendUserData>>? value) =>
      _chatMembersFuture = value;

  @override
  Timer? get stateMarkMessagesReadDebounce => _markMessagesReadDebounce;

  @override
  set stateMarkMessagesReadDebounce(Timer? value) =>
      _markMessagesReadDebounce = value;

  @override
  Set<String> get stateLocallyReadMessageIds => _locallyReadMessageIds;

  @override
  List<ChatMessageData> get stateMessages => _messages;

  @override
  DocumentSnapshot<Map<String, dynamic>>? get stateOldestLoadedDoc =>
      _oldestLoadedDoc;

  @override
  set stateOldestLoadedDoc(DocumentSnapshot<Map<String, dynamic>>? value) =>
      _oldestLoadedDoc = value;

  @override
  bool get stateIsInitialLoadingMessages => _isInitialLoadingMessages;

  @override
  set stateIsInitialLoadingMessages(bool value) =>
      _isInitialLoadingMessages = value;

  @override
  bool get stateIsLoadingOlderMessages => _isLoadingOlderMessages;

  @override
  set stateIsLoadingOlderMessages(bool value) =>
      _isLoadingOlderMessages = value;

  @override
  bool get stateHasMoreOlderMessages => _hasMoreOlderMessages;

  @override
  set stateHasMoreOlderMessages(bool value) => _hasMoreOlderMessages = value;

  @override
  bool get statePaginationInitialized => _paginationInitialized;

  @override
  set statePaginationInitialized(bool value) => _paginationInitialized = value;

  @override
  late final ChatConversationContentActions content = ChatConversationContent(
    this,
  );

  @override
  late final ChatConversationControllerActions controller =
      ChatConversationController(this);

  @override
  final messageController = TextEditingController();
  @override
  final messageFocusNode = FocusNode();
  @override
  final chatScrollController = ScrollController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _newMessagesSubscription;
  Future<List<FriendUserData>>? _chatMembersFuture;
  Timer? _markMessagesReadDebounce;
  @override
  bool isSharingChatLocation = false;
  @override
  bool isUploadingPhotoAttachment = false;
  @override
  String? pendingPhotoAttachmentPath;
  @override
  ChatMessageData? replyingToMessage;
  @override
  bool hasScrolledToLatestMessage = false;
  @override
  bool scrollToLatestAfterNextMessage = false;
  @override
  int renderedMessageCount = 0;
  final Set<String> _locallyReadMessageIds = {};

  // Messages are loaded in pages. The initial page is only the latest 10.
  final List<ChatMessageData> _messages = [];
  DocumentSnapshot<Map<String, dynamic>>? _oldestLoadedDoc;
  bool _isInitialLoadingMessages = true;
  bool _isLoadingOlderMessages = false;
  bool _hasMoreOlderMessages = true;
  bool _paginationInitialized = false;

  @override
  void initState() {
    super.initState();
    _chatMembersFuture = loadChatMembers(widget.chat);
    chatScrollController.addListener(controller.onScroll);
    controller.markCurrentChatNotificationsRead();
    unawaited(controller.loadInitialMessages());
  }

  @override
  void didUpdateWidget(ChatConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id ||
        oldWidget.chat.memberIds.join('|') != widget.chat.memberIds.join('|')) {
      _chatMembersFuture = loadChatMembers(widget.chat);
    }
  }

  @override
  void dispose() {
    _markMessagesReadDebounce?.cancel();
    _newMessagesSubscription?.cancel();
    chatScrollController.removeListener(controller.onScroll);
    messageFocusNode.dispose();
    messageController.dispose();
    chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final currentUid = firebaseUser?.uid ?? currentUser.uid;
    final title = widget.chat.titleForCurrentUser(currentUid);
    final chatPhotoUrl = widget.chat.directPhotoUrlForCurrentUser(currentUid);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canModerateGroupChat =
        widget.chat.isGroup &&
        (widget.chat.isOwner(currentUid) ||
            widget.chat.moderatorIds.contains(currentUid) ||
            currentUserCanModerateCountry(
              widget.chat.countryCode,
              community: true,
            ));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: widget.chat.isGroup ? 72 : null,
        titleSpacing: widget.chat.isGroup ? 0 : null,
        title: widget.chat.isGroup
            ? content.groupChatTitle(title)
            : content.directChatTitle(currentUid, title, chatPhotoUrl),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: controller.readOnly
            ? <Widget>[]
            : widget.chat.isGroup
            ? [
                if (canModerateGroupChat)
                  IconButton(
                    tooltip: 'Модерация',
                    onPressed: controller.openGroupSettings,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                  ),
                IconButton(
                  tooltip: 'Group info',
                  onPressed: controller.openGroupSettings,
                  icon: const Icon(Icons.info_outline),
                ),
                PopupMenuButton<String>(
                  color: panel,
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'remove_chat') {
                      unawaited(controller.removeCurrentChat());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remove_chat',
                      child: Row(
                        children: [
                          Icon(
                            currentUserCanDeleteGroupChat(widget.chat)
                                ? Icons.delete_outline
                                : Icons.logout,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          CcsText(chatRemovalButtonLabel(widget.chat)),
                        ],
                      ),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Open profile',
                  onPressed: () => controller.openChatUserProfile(currentUid),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
                PopupMenuButton<String>(
                  color: panel,
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'remove_chat') {
                      unawaited(controller.removeCurrentChat());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remove_chat',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          CcsText(chatRemovalButtonLabel(widget.chat)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Builder(
                builder: (context) {
                  final messages = List<ChatMessageData>.from(_messages);
                  controller.updateChatScrollForMessages(messages.length);

                  if (_isInitialLoadingMessages) {
                    return const Center(
                      child: CircularProgressIndicator(color: blue),
                    );
                  }

                  if (messages.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: EmptyStateCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'No messages yet',
                        text: 'Send the first message.',
                      ),
                    );
                  }

                  Widget listWithUsers(Map<String, FriendUserData> usersById) {
                    String previousDateLabel = '';
                    String previousSenderUid = '';
                    final children = <Widget>[];
                    for (final message in messages) {
                      final dateLabel = chatDateDividerLabel(
                        message.createdAtMillis,
                      );
                      if (dateLabel.isNotEmpty &&
                          dateLabel != previousDateLabel) {
                        children.add(chatDateDivider(dateLabel));
                        previousDateLabel = dateLabel;
                        previousSenderUid = '';
                      }
                      final showAuthorHeader =
                          message.senderUid.isEmpty ||
                          message.senderUid != previousSenderUid;
                      children.add(
                        content.messageBubble(
                          message,
                          currentUid,
                          usersById,
                          showAuthorHeader: showAuthorHeader,
                        ),
                      );
                      previousSenderUid = message.senderUid;
                    }

                    return ListView(
                      controller: chatScrollController,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      children: [
                        ...children.reversed,
                        if (_hasMoreOlderMessages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Center(
                              child: CcsText(
                                'Scroll up to load older messages',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (_isLoadingOlderMessages)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: blue,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }

                  return FutureBuilder<List<FriendUserData>>(
                    future: _chatMembersFuture,
                    builder: (context, usersSnapshot) {
                      final members =
                          usersSnapshot.data ??
                          [
                            for (final uid in widget.chat.memberIds)
                              fallbackChatMember(widget.chat, uid),
                          ];
                      final usersById = <String, FriendUserData>{
                        for (final member in members) member.uid: member,
                      };

                      return listWithUsers(usersById);
                    },
                  );
                },
              ),
            ),
          ),
          if (controller.readOnly)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CcsText(
                  trText(
                    'Read-only monitoring. You are not a member of this group.',
                  ),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              bottom: !keyboardOpen,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, 6, 8, keyboardOpen ? 0 : 8),
                decoration: BoxDecoration(
                  color: panelGlass,
                  border: const Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replyingToMessage != null) ...[
                      messageReplyPreviewCard(
                        MessageReplyPreviewData(
                          messageId: replyingToMessage!.id,
                          username: replyingToMessage!.senderUsername,
                          text: replyingToMessage!.text,
                          photoUrl: replyingToMessage!.photoUrl,
                        ),
                        compact: true,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => replyingToMessage = null),
                          icon: const Icon(Icons.close, size: 16),
                          label: CcsText(trText('Cancel reply')),
                        ),
                      ),
                    ],
                    if (pendingPhotoAttachmentPath != null)
                      stagedChatPhotoPreview(
                        localPhotoPath: pendingPhotoAttachmentPath!,
                        isBusy: isUploadingPhotoAttachment,
                        onRemove: () {
                          setState(() => pendingPhotoAttachmentPath = null);
                        },
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Share location',
                          onPressed: isSharingChatLocation
                              ? null
                              : controller.shareLiveLocation,
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(foregroundColor: blue),
                          icon: Icon(
                            isSharingChatLocation
                                ? Icons.hourglass_top
                                : Icons.my_location,
                          ),
                        ),
                        IconButton(
                          tooltip: trText('Photo'),
                          onPressed: isUploadingPhotoAttachment
                              ? null
                              : controller.attachPhoto,
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(foregroundColor: blue),
                          icon: Icon(
                            isUploadingPhotoAttachment
                                ? Icons.hourglass_top
                                : Icons.photo_camera_outlined,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: MentionTextField(
                            allowedUserIds: widget.chat.memberIds,
                            controller: messageController,
                            focusNode: messageFocusNode,
                            minLines: 1,
                            maxLines: 3,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: trText('Message'),
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.06),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Colors.white12,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Colors.white12,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: blue),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: controller.sendMessage,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: blue,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
