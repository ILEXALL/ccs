import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show chatMessagesCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show uniqueNonEmptyStrings;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/data/chat_messages.dart'
    show
        currentUserCanModerateChat,
        deleteChatMessage,
        editChatMessage,
        markChatMessagesReadByCurrentUser,
        sendChatMessage;
import 'package:ccs_app/features/community/chats/data/chat_photos.dart'
    show uploadChatAttachmentPhoto;
import 'package:ccs_app/features/community/chats/data/chat_queries.dart'
    show latestChatMessagesQuery;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;
import 'package:ccs_app/features/community/chats/widgets/chat_actions.dart'
    show confirmAndRemoveChat;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show showEmojiReactionPicker;
import 'package:ccs_app/features/community/chats/widgets/message_status.dart'
    show chatMessagePageSize;
import 'package:ccs_app/features/community/chats/data/chat_session_cache.dart'
    show chatMessageSessionCache, chatOldestMessageDocSessionCache;
import 'package:ccs_app/features/community/groups/screens/group_settings_screen.dart'
    show GroupSettingsScreen;
import 'package:ccs_app/features/map/data/chat_location.dart'
    show shareChatLiveLocation;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show markChatNotificationsRead;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/features/community/chats/controllers/chat_conversation_view_state.dart';

/// Coordinates actions and data loading for ChatConversationScreen.
class ChatConversationController implements ChatConversationControllerActions {
  final ChatConversationViewState host;
  ChatConversationController(this.host);

  @override
  bool get readOnly =>
      host.widget.readOnly ||
      (host.widget.chat.isGroup &&
          !host.widget.chat.memberIds.contains(
            FirebaseAuth.instance.currentUser?.uid,
          ));

  @override
  void cacheMessages() {
    chatMessageSessionCache[host.widget.chat.id] = List<ChatMessageData>.from(
      host.stateMessages,
    );
    final oldest = host.stateOldestLoadedDoc;
    if (oldest != null) {
      chatOldestMessageDocSessionCache[host.widget.chat.id] = oldest;
    }
  }

  @override
  void markCurrentChatNotificationsRead({Duration delay = Duration.zero}) {
    if (readOnly) return;
    if (delay == Duration.zero) {
      unawaited(markChatNotificationsRead(host.widget.chat.id));
      return;
    }

    Future<void>.delayed(delay, () async {
      if (!host.mounted) {
        return;
      }

      await markChatNotificationsRead(host.widget.chat.id);
    });
  }

  @override
  void scheduleMarkVisibleMessagesRead({
    Duration delay = const Duration(milliseconds: 650),
  }) {
    host.stateMarkMessagesReadDebounce?.cancel();
    host.stateMarkMessagesReadDebounce = Timer(delay, () {
      unawaited(markVisibleMessagesRead());
    });
  }

  @override
  Future<void> markVisibleMessagesRead() async {
    if (readOnly) return;
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    if (currentUid.trim().isEmpty) {
      return;
    }

    final unreadMessages = host.stateMessages
        .where(
          (message) =>
              message.senderUid != currentUid &&
              !message.isLocalPending &&
              !message.sendFailed &&
              !message.readByUserIds.contains(currentUid) &&
              !host.stateLocallyReadMessageIds.contains(message.id),
        )
        .take(25)
        .toList();

    if (unreadMessages.isEmpty) {
      return;
    }

    final unreadIds = unreadMessages.map((message) => message.id).toSet();
    host.stateLocallyReadMessageIds.addAll(unreadIds);

    try {
      await markChatMessagesReadByCurrentUser(
        chatId: host.widget.chat.id,
        messages: unreadMessages,
      );

      if (!host.mounted) {
        return;
      }

      host.updateView(() {
        for (var index = 0; index < host.stateMessages.length; index++) {
          final message = host.stateMessages[index];
          if (!unreadIds.contains(message.id)) {
            continue;
          }

          host.stateMessages[index] = message.copyWith(
            readByUserIds: uniqueNonEmptyStrings([
              ...message.readByUserIds,
              currentUid,
            ]),
          );
        }
        cacheMessages();
      });
    } catch (error, stack) {
      host.stateLocallyReadMessageIds.removeAll(unreadIds);
      debugPrint('Chat messages could not be marked read: $error');
      debugPrint('$stack');
    }
  }

  @override
  void mergeMessages(Iterable<ChatMessageData> incoming) {
    final byId = <String, ChatMessageData>{
      for (final message in host.stateMessages) message.id: message,
    };
    for (final message in incoming) {
      if (message.text.trim().isEmpty && message.photoUrl.trim().isEmpty) {
        continue;
      }
      byId[message.id] = message;
    }
    host.stateMessages
      ..clear()
      ..addAll(byId.values);
    host.stateMessages.sort(
      (a, b) => a.createdAtMillis.compareTo(b.createdAtMillis),
    );
    cacheMessages();
  }

  @override
  void updateMessage(
    String messageId,
    ChatMessageData Function(ChatMessageData message) update,
  ) {
    final index = host.stateMessages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) {
      return;
    }

    host.stateMessages[index] = update(host.stateMessages[index]);
    cacheMessages();
  }

  @override
  Future<void> loadInitialMessages() async {
    final cachedMessages = chatMessageSessionCache[host.widget.chat.id];
    if (cachedMessages != null) {
      host.stateMessages
        ..clear()
        ..addAll(cachedMessages);
      host.stateOldestLoadedDoc =
          chatOldestMessageDocSessionCache[host.widget.chat.id];
      host.statePaginationInitialized =
          host.stateOldestLoadedDoc != null || host.stateMessages.isEmpty;
      host.stateHasMoreOlderMessages =
          host.stateMessages.length >= chatMessagePageSize;
      if (host.mounted) {
        host.updateView(() => host.stateIsInitialLoadingMessages = false);
        scheduleScrollToLatestMessage();
      }
      scheduleMarkVisibleMessagesRead();
      startNewMessagesListener();
      return;
    }

    try {
      final snapshot = await latestChatMessagesQuery(
        host.widget.chat.id,
      ).debugGet(null, 'chat: initial latest messages');

      if (!host.mounted) {
        return;
      }

      final loaded = snapshot.docs
          .map((doc) => ChatMessageData.fromFirestore(doc))
          .where(
            (message) =>
                message.text.trim().isNotEmpty ||
                message.photoUrl.trim().isNotEmpty,
          )
          .toList();
      loaded.sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));

      host.updateView(() {
        host.stateMessages
          ..clear()
          ..addAll(loaded);
        host.stateOldestLoadedDoc = snapshot.docs.isEmpty
            ? null
            : snapshot.docs.last;
        host.stateHasMoreOlderMessages =
            snapshot.docs.length >= chatMessagePageSize;
        host.statePaginationInitialized = true;
        host.stateIsInitialLoadingMessages = false;
      });
      cacheMessages();
      scheduleScrollToLatestMessage();
      markCurrentChatNotificationsRead();
      scheduleMarkVisibleMessagesRead();
      startNewMessagesListener();
    } catch (error, stack) {
      debugPrint('Initial chat messages could not load: $error');
      debugPrint('$stack');
      if (host.mounted) {
        host.updateView(() => host.stateIsInitialLoadingMessages = false);
      }
      startNewMessagesListener();
    }
  }

  @override
  void startNewMessagesListener() {
    host.stateNewMessagesSubscription?.cancel();

    final query = latestChatMessagesQuery(host.widget.chat.id);

    host.stateNewMessagesSubscription = query
        .debugSnapshots('chat: new messages listener')
        .listen(
          (snapshot) {
            if (!host.mounted || snapshot.docs.isEmpty) {
              return;
            }

            final shouldFollow = isNearLatestMessage();
            final incoming = snapshot.docs
                .map((doc) => ChatMessageData.fromFirestore(doc))
                .where(
                  (message) =>
                      message.text.trim().isNotEmpty ||
                      message.photoUrl.trim().isNotEmpty,
                )
                .toList();

            host.updateView(() => mergeMessages(incoming));
            markCurrentChatNotificationsRead(delay: const Duration(seconds: 1));
            scheduleMarkVisibleMessagesRead();
            if (shouldFollow || host.scrollToLatestAfterNextMessage) {
              scheduleScrollToLatestMessage();
            }
          },
          onError: (Object error, StackTrace stack) {
            debugPrint('New chat messages listener failed: $error');
            debugPrint('$stack');
          },
        );
  }

  @override
  void onScroll() {
    if (!host.chatScrollController.hasClients) return;
    final position = host.chatScrollController.position;
    // Load older messages when the user scrolls near the top.
    if (position.maxScrollExtent - position.pixels <= 120 &&
        host.stateHasMoreOlderMessages &&
        !host.stateIsLoadingOlderMessages &&
        host.statePaginationInitialized) {
      unawaited(loadOlderMessages());
    }
  }

  @override
  Future<void> loadOlderMessages() async {
    if (host.stateIsLoadingOlderMessages || !host.stateHasMoreOlderMessages)
      return;
    if (host.stateOldestLoadedDoc == null) return;

    host.updateView(() => host.stateIsLoadingOlderMessages = true);

    try {
      final snapshot = await chatMessagesCollection(host.widget.chat.id)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(host.stateOldestLoadedDoc!)
          .limit(chatMessagePageSize)
          .debugGet(null, 'chat: load older messages');

      if (!host.mounted) return;

      final older = snapshot.docs
          .map((doc) => ChatMessageData.fromFirestore(doc))
          .where(
            (message) =>
                message.text.trim().isNotEmpty ||
                message.photoUrl.trim().isNotEmpty,
          )
          .toList()
          .reversed
          .toList();

      host.updateView(() {
        if (older.isNotEmpty) {
          host.stateOldestLoadedDoc = snapshot.docs.last;
          mergeMessages(older);
        }
        host.stateHasMoreOlderMessages =
            snapshot.docs.length >= chatMessagePageSize;
        host.stateIsLoadingOlderMessages = false;
      });
      scheduleMarkVisibleMessagesRead();
    } catch (error, stack) {
      debugPrint('Older chat messages could not load: $error');
      debugPrint('$stack');
      if (host.mounted)
        host.updateView(() => host.stateIsLoadingOlderMessages = false);
    }
  }

  @override
  bool isNearLatestMessage() {
    if (!host.chatScrollController.hasClients) {
      return true;
    }

    final position = host.chatScrollController.position;
    return position.pixels - position.minScrollExtent < 140;
  }

  @override
  void scheduleScrollToLatestMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted || !host.chatScrollController.hasClients) {
        return;
      }

      host.chatScrollController.jumpTo(
        host.chatScrollController.position.minScrollExtent,
      );
    });
  }

  @override
  void updateChatScrollForMessages(int messageCount) {
    final firstMessageLayout = !host.hasScrolledToLatestMessage;
    final receivedNewMessage = messageCount > host.renderedMessageCount;
    final shouldFollowLatest =
        firstMessageLayout ||
        (receivedNewMessage &&
            (host.scrollToLatestAfterNextMessage || isNearLatestMessage()));

    host.renderedMessageCount = messageCount;
    if (firstMessageLayout) {
      host.hasScrolledToLatestMessage = true;
    }
    if (receivedNewMessage) {
      host.scrollToLatestAfterNextMessage = false;
    }
    if (shouldFollowLatest) {
      scheduleScrollToLatestMessage();
    }
  }

  @override
  Future<void> attachPhoto() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (readOnly) return;
    if (host.isUploadingPhotoAttachment) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before sending messages.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    host.updateView(() => host.isUploadingPhotoAttachment = true);

    try {
      final path = await pickPhotoFromPhone(viewContext, cropPhoto: false);

      if (!(host.mounted && viewContext.mounted) ||
          path == null ||
          path.trim().isEmpty) {
        return;
      }

      host.updateView(() => host.pendingPhotoAttachmentPath = path);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not attach photo: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isUploadingPhotoAttachment = false);
      }
    }
  }

  @override
  Future<void> sendMessage() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (readOnly) return;
    final text = host.messageController.text.trim();
    final localPhotoPath = host.pendingPhotoAttachmentPath?.trim() ?? '';
    final hasPhoto = localPhotoPath.isNotEmpty;
    final replyMessage = host.replyingToMessage;
    final replyTo = replyMessage == null
        ? null
        : MessageReplyPreviewData(
            messageId: replyMessage.id,
            username: replyMessage.senderUsername,
            text: replyMessage.text,
            photoUrl: replyMessage.photoUrl,
          );

    if ((!hasPhoto && text.isEmpty) || host.isUploadingPhotoAttachment) {
      return;
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Log in before sending messages.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final createdAtMillis = DateTime.now().millisecondsSinceEpoch;
    final messageId = chatMessagesCollection(host.widget.chat.id).doc().id;

    host.updateView(() {
      host.isUploadingPhotoAttachment = hasPhoto;
    });

    try {
      String photoUrl = '';
      if (hasPhoto) {
        photoUrl = await uploadChatAttachmentPhoto(
          scope: 'chats',
          parentId: host.widget.chat.id,
          messageId: messageId,
          localPhotoPath: localPhotoPath,
        );
      }

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      final pendingMessage = ChatMessageData.pending(
        id: messageId,
        senderUid: firebaseUser.uid,
        senderUsername: currentUser.username,
        text: text,
        photoUrl: photoUrl,
        createdAtMillis: createdAtMillis,
        replyTo: replyTo,
      );

      host.messageController.clear();
      host.updateView(() {
        host.pendingPhotoAttachmentPath = null;
        host.replyingToMessage = null;
        mergeMessages([pendingMessage]);
        host.scrollToLatestAfterNextMessage = true;
      });
      scheduleScrollToLatestMessage();

      await sendChatMessage(
        chatId: host.widget.chat.id,
        text: text,
        photoUrl: photoUrl,
        chat: host.widget.chat,
        messageId: messageId,
        clientCreatedAtMillis: createdAtMillis,
        replyTo: replyTo,
      );

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() {
        updateMessage(
          messageId,
          (message) => message.copyWith(isLocalPending: false),
        );
      });
      markCurrentChatNotificationsRead(delay: const Duration(seconds: 1));
      scheduleScrollToLatestMessage();
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() {
        host.stateMessages.removeWhere((message) => message.id == messageId);
      });

      if (host.messageController.text.trim().isEmpty) {
        host.messageController.text = text;
        host.messageController.selection = TextSelection.collapsed(
          offset: host.messageController.text.length,
        );
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            hasPhoto
                ? 'Could not attach photo: $error'
                : 'Could not send message: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isUploadingPhotoAttachment = false);
      }
    }
  }

  @override
  Future<void> shareLiveLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (readOnly) return;
    if (host.isSharingChatLocation) {
      return;
    }

    host.updateView(() => host.isSharingChatLocation = true);

    try {
      await shareChatLiveLocation(viewContext, host.widget.chat);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not share location: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isSharingChatLocation = false);
      }
    }
  }

  @override
  String? otherUserId(String currentUid) {
    if (host.widget.chat.isGroup) {
      return null;
    }

    for (final uid in host.widget.chat.memberIds) {
      if (uid != currentUid && uid.trim().isNotEmpty) {
        return uid;
      }
    }

    return null;
  }

  @override
  String otherUsername(String currentUid) {
    for (var index = 0; index < host.widget.chat.memberIds.length; index++) {
      final uid = host.widget.chat.memberIds[index];
      if (uid == currentUid) {
        continue;
      }

      if (index < host.widget.chat.memberUsernames.length) {
        return host.widget.chat.memberUsernames[index];
      }
    }

    return '';
  }

  @override
  void openChatUserProfile(String currentUid) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final uid = otherUserId(currentUid);

    if (uid == null) {
      return;
    }

    openUserProfile(
      viewContext,
      uid: uid,
      fallbackUsername: otherUsername(currentUid),
    );
  }

  @override
  Future<void> openGroupSettings() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (readOnly) return;
    final removed = await Navigator.push<bool>(
      viewContext,
      appPageRoute(builder: (_) => GroupSettingsScreen(chat: host.widget.chat)),
    );
    if (removed == true && (host.mounted && viewContext.mounted)) {
      Navigator.of(viewContext).maybePop();
    }
  }

  @override
  Future<void> removeCurrentChat() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final removed = await confirmAndRemoveChat(viewContext, host.widget.chat);
    if (removed && (host.mounted && viewContext.mounted)) {
      Navigator.of(viewContext).maybePop();
    }
  }

  @override
  Future<void> reactToChatMessage(
    ChatMessageData message, {
    String? preferredEmoji,
  }) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    if (uid.trim().isEmpty || message.isLocalPending) return;

    final currentEmoji = message.reactions[uid] ?? '';
    String? selected = preferredEmoji;
    if (selected != null && selected == currentEmoji) {
      selected = '';
    } else {
      selected ??= await showEmojiReactionPicker(
        viewContext,
        currentEmoji: currentEmoji,
      );
    }
    if (!(host.mounted && viewContext.mounted) || selected == null) return;

    try {
      await chatMessagesCollection(
        host.widget.chat.id,
      ).doc(message.id).debugUpdate({
        'reactions.$uid': selected.trim().isEmpty
            ? FieldValue.delete()
            : selected.trim(),
      }, 'chat: react to message');
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not update reaction')}: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Future<void> showOwnMessageActions(ChatMessageData message) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    final mine = message.senderUid == currentUid;
    final canModerate = await currentUserCanModerateChat(host.widget.chat.id);
    final canDelete = mine || canModerate;

    if (message.isLocalPending) {
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: viewContext,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: panelGlass,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: blue),
                  title: CcsText(
                    trText('Reply'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'reply'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined, color: blue),
                  title: CcsText(
                    trText('React'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'react'),
                ),
                if (mine)
                  ListTile(
                    leading: const Icon(Icons.edit, color: blue),
                    title: const CcsText(
                      'Edit message',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                if (canDelete)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    title: const CcsText(
                      'Delete message',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!(host.mounted && viewContext.mounted) || action == null) {
      return;
    }

    if (action == 'reply') {
      host.updateView(() => host.replyingToMessage = message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if ((host.mounted && viewContext.mounted)) {
          host.messageFocusNode.requestFocus();
        }
      });
    } else if (action == 'react') {
      await reactToChatMessage(message);
    } else if (action == 'edit') {
      await showEditMessageDialog(message);
    } else if (action == 'delete') {
      await deleteMessageImmediately(message);
    }
  }

  @override
  Future<void> deleteMessageImmediately(ChatMessageData message) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!(host.mounted && viewContext.mounted) || message.isLocalPending) {
      return;
    }

    final index = host.stateMessages.indexWhere(
      (item) => item.id == message.id,
    );
    final removedMessage = index >= 0 ? host.stateMessages[index] : message;

    if (index >= 0) {
      host.updateView(() {
        host.stateMessages.removeAt(index);
      });
    }

    try {
      await deleteChatMessage(chatId: host.widget.chat.id, message: message);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (index >= 0 &&
          !host.stateMessages.any((item) => item.id == removedMessage.id)) {
        host.updateView(() {
          final restoreIndex = index
              .clamp(0, host.stateMessages.length)
              .toInt();
          host.stateMessages.insert(restoreIndex, removedMessage);
        });
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            '${trText('Could not delete message')}: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Future<void> showEditMessageDialog(ChatMessageData message) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final controller = TextEditingController(text: message.text);

    final updatedText = await showDialog<String>(
      context: viewContext,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(
            trText('Edit message'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: MentionTextField(
            allowedUserIds: host.widget.chat.memberIds,
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: trText('Message'),
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: blue),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: CcsText(trText('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(backgroundColor: blue),
              child: CcsText(
                trText('Save'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!(host.mounted && viewContext.mounted) ||
        updatedText == null ||
        updatedText.trim() == message.text.trim()) {
      return;
    }

    try {
      await editChatMessage(
        chatId: host.widget.chat.id,
        message: message,
        text: updatedText,
      );
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            '${trText('Could not edit message')}: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Future<void> confirmDeleteMessage(ChatMessageData message) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final shouldDelete = await showDialog<bool>(
      context: viewContext,
      builder: (context) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(
            trText('Delete message?'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: CcsText(
            trText('This message will be deleted from the chat.'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: CcsText(trText('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: CcsText(
                trText('Delete'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (!(host.mounted && viewContext.mounted) || shouldDelete != true) {
      return;
    }

    await deleteMessageImmediately(message);
  }
}
