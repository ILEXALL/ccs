import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase, timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        ConfirmedFirestoreTransaction,
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        FirestoreDebugTransactionExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection, currentUser, currentUserHomeCountryCode;
import 'package:ccs_app/features/community/chats/data/chat_photos.dart'
    show uploadChatAttachmentPhoto;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData, messageReactionsFromFirebase;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show chatDateDivider, chatDateDividerLabel;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show showEmojiReactionPicker;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityContentCountryCode, ensureCommunityProfileCountry;
import 'package:ccs_app/features/community/global_chat/data/global_chat_config.dart'
    show
        globalChatMessagePageSize,
        globalChatMessageSendCooldown,
        legacyLatvianGlobalMessagesSnapshotFuture;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show isFirestorePermissionDenied;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry, currentUserHasCommunityModerationAccess;
import 'package:ccs_app/features/notifications/data/community_notifications.dart'
    show sendCommunityPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show notifyStaffAboutCommunityEvent;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/countries.dart' show countryNamesByIso;
import 'package:ccs_app/features/community/global_chat/controllers/global_chat_view_state.dart';

/// Coordinates actions and data loading for GlobalChatTab.
class GlobalChatController implements GlobalChatControllerActions {
  final GlobalChatViewState host;
  GlobalChatController(this.host);

  String? _onlineListenerUserId;

  @override
  void updateOnlineUsersStream() {
    final uid =
        host.widget.isActive &&
            currentUser.role == UserRole.admin &&
            currentUser.uid.isNotEmpty
        ? currentUser.uid
        : null;
    if (uid == _onlineListenerUserId) return;
    _onlineListenerUserId = uid;
    host.onlineUsersStream = uid == null
        ? null
        : usersCollection()
              .where('isOnline', isEqualTo: true)
              .debugSnapshots('global chat: admin live online users counter');
  }

  @override
  void handleLanguageChanged() {
    if (!host.mounted) {
      return;
    }

    host.updateView(() {});
  }

  @override
  CollectionReference<Map<String, dynamic>> get globalChatCollection =>
      FirebaseFirestore.instance.collection('global_chat');

  @override
  String get selectedCommunityCountryCode => communityCountrySelection.value;

  @override
  bool get canPostInSelectedCommunity =>
      countryNamesByIso.containsKey(selectedCommunityCountryCode);

  @override
  int get activeGlobalChatQueryPageSize => globalChatMessagePageSize;

  @override
  Query<Map<String, dynamic>> get latestGlobalChatMessagesQuery {
    return globalChatCollection
        .where('countryCode', isEqualTo: selectedCommunityCountryCode)
        .orderBy('timestamp', descending: true)
        .limit(activeGlobalChatQueryPageSize);
  }

  @override
  bool get canModerateGlobalChat => currentUserCanModerateCountry(
    selectedCommunityCountryCode,
    community: true,
  );

  @override
  Future<void> loadGlobalChatModeratorAccess() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      return;
    }

    await currentUserHasCommunityModerationAccess();
    if (host.mounted) {
      host.updateView(() {});
    }
  }

  @override
  void handleCommunityCountryChanged() {
    if (!host.mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    host.updateView(() {
      host.stateGlobalMessages.clear();
      host.stateOldestLoadedGlobalMessageDoc = null;
      host.stateIsInitialLoadingGlobalMessages = true;
      host.stateIsLoadingOlderGlobalMessages = false;
      host.stateHasMoreOlderGlobalMessages = true;
      host.stateGlobalPaginationInitialized = false;
      host.stateLegacyLatvianMessagesLoaded = false;
      host.replyingToGlobalMessage = null;
      host.pendingPhotoAttachmentPath = null;
    });
    startGlobalMessagesListener();
  }

  @override
  bool globalMessageHasContent(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return stringFromFirebase(data['text'], '').trim().isNotEmpty ||
        stringFromFirebase(
          data['photoUrl'],
          stringFromFirebase(data['imageUrl'], ''),
        ).trim().isNotEmpty;
  }

  @override
  void mergeGlobalMessages(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> incoming,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final message in host.stateGlobalMessages) message.id: message,
    };
    for (final message in incoming) {
      if (!globalMessageHasContent(message) ||
          communityContentCountryCode(message.data()) !=
              selectedCommunityCountryCode) {
        continue;
      }
      byId[message.id] = message;
    }

    host.stateGlobalMessages
      ..clear()
      ..addAll(byId.values);
    host.stateGlobalMessages.sort((a, b) {
      final aMillis = timestampMillisFromFirebase(a.data()['timestamp']);
      final bMillis = timestampMillisFromFirebase(b.data()['timestamp']);
      return aMillis.compareTo(bMillis);
    });
  }

  @override
  void startGlobalMessagesListener({bool useUnindexedFallback = false}) {
    host.stateGlobalMessagesSubscription?.cancel();
    final listenerCountryCode = selectedCommunityCountryCode;
    final query = useUnindexedFallback
        ? globalChatCollection.orderBy('timestamp', descending: true).limit(200)
        : latestGlobalChatMessagesQuery;

    host.stateGlobalMessagesSubscription = query
        .debugSnapshots(
          useUnindexedFallback
              ? 'global chat: bounded unindexed fallback listener'
              : 'global chat: latest messages listener',
        )
        .listen(
          (snapshot) {
            if (!host.mounted ||
                selectedCommunityCountryCode != listenerCountryCode) {
              return;
            }

            final shouldFollowLatest = isNearLatestGlobalMessage();
            final shouldInitializePagination =
                !host.stateGlobalPaginationInitialized ||
                (host.stateOldestLoadedGlobalMessageDoc == null &&
                    host.stateGlobalMessages.isEmpty &&
                    snapshot.docs.isNotEmpty);
            final removedMessageIds = snapshot.docChanges
                .where((change) => change.type == DocumentChangeType.removed)
                .map((change) => change.doc.id)
                .toSet();

            host.updateView(() {
              if (useUnindexedFallback) {
                host.stateOldestLoadedGlobalMessageDoc = null;
                host.stateHasMoreOlderGlobalMessages = false;
                host.stateGlobalPaginationInitialized = true;
              } else if (shouldInitializePagination) {
                host.stateOldestLoadedGlobalMessageDoc = snapshot.docs.isEmpty
                    ? null
                    : snapshot.docs.last;
                host.stateHasMoreOlderGlobalMessages =
                    snapshot.docs.length >= activeGlobalChatQueryPageSize;
                host.stateGlobalPaginationInitialized = true;
              }
              if (removedMessageIds.isNotEmpty) {
                host.stateGlobalMessages.removeWhere(
                  (message) => removedMessageIds.contains(message.id),
                );
              }
              mergeGlobalMessages(snapshot.docs);
              host.stateIsInitialLoadingGlobalMessages = false;
              host.stateGlobalMessagesLoadFailed = false;
            });

            if (shouldFollowLatest ||
                host.stateScrollGlobalChatToLatestAfterSend) {
              host.stateScrollGlobalChatToLatestAfterSend = false;
              scheduleGlobalChatScrollToLatest();
            }
            if (selectedCommunityCountryCode == 'LV' &&
                !snapshot.metadata.isFromCache &&
                snapshot.docs.length < activeGlobalChatQueryPageSize &&
                !host.stateLegacyLatvianMessagesLoaded) {
              unawaited(loadLegacyLatvianGlobalMessages());
            }
          },
          onError: (Object error, StackTrace stack) {
            debugPrint('Global chat messages listener failed: $error');
            debugPrint('$stack');
            if (!host.mounted ||
                selectedCommunityCountryCode != listenerCountryCode) {
              return;
            }
            final errorText = error.toString().toLowerCase();
            final missingIndex =
                (error is FirebaseException &&
                    error.code == 'failed-precondition') ||
                errorText.contains('index');
            if (!useUnindexedFallback && missingIndex) {
              debugPrint(
                'Regional Global chat index is unavailable; using a bounded '
                'real-time fallback until the index is deployed.',
              );
              startGlobalMessagesListener(useUnindexedFallback: true);
              return;
            }
            if (host.mounted) {
              host.updateView(() {
                host.stateIsInitialLoadingGlobalMessages = false;
                host.stateGlobalMessagesLoadFailed = true;
              });
            }
          },
        );
  }

  @override
  Future<void> loadLegacyLatvianGlobalMessages() async {
    if (host.stateLegacyLatvianMessagesLoaded ||
        selectedCommunityCountryCode != 'LV') {
      return;
    }
    host.stateLegacyLatvianMessagesLoaded = true;
    final request = legacyLatvianGlobalMessagesSnapshotFuture ??=
        globalChatCollection
            .orderBy('timestamp', descending: true)
            .limit(100)
            .debugGet(null, 'global chat: legacy Latvian messages');
    try {
      final snapshot = await request;
      if (!host.mounted || selectedCommunityCountryCode != 'LV') return;
      host.updateView(() {
        mergeGlobalMessages(
          snapshot.docs.where((doc) => !doc.data().containsKey('countryCode')),
        );
      });
    } catch (error) {
      if (identical(legacyLatvianGlobalMessagesSnapshotFuture, request)) {
        legacyLatvianGlobalMessagesSnapshotFuture = null;
      }
      host.stateLegacyLatvianMessagesLoaded = false;
      debugPrint('Legacy Latvian global messages could not load: $error');
    }
  }

  @override
  void onGlobalChatScroll() {
    if (!host.globalChatScrollController.hasClients) {
      return;
    }

    final position = host.globalChatScrollController.position;
    if (position.maxScrollExtent - position.pixels <= 120 &&
        !host.stateLegacyLatvianMessagesLoaded) {
      unawaited(loadLegacyLatvianGlobalMessages());
    }
    if (position.maxScrollExtent - position.pixels <= 120 &&
        host.stateHasMoreOlderGlobalMessages &&
        !host.stateIsLoadingOlderGlobalMessages &&
        host.stateGlobalPaginationInitialized) {
      unawaited(loadOlderGlobalMessages());
    }
  }

  @override
  Future<void> loadOlderGlobalMessages() async {
    if (host.stateIsLoadingOlderGlobalMessages ||
        !host.stateHasMoreOlderGlobalMessages) {
      return;
    }

    final oldestDoc = host.stateOldestLoadedGlobalMessageDoc;
    if (oldestDoc == null) {
      return;
    }

    host.updateView(() => host.stateIsLoadingOlderGlobalMessages = true);

    try {
      final snapshot = await globalChatCollection
          .where('countryCode', isEqualTo: selectedCommunityCountryCode)
          .orderBy('timestamp', descending: true)
          .startAfterDocument(oldestDoc)
          .limit(activeGlobalChatQueryPageSize)
          .debugGet(null, 'global chat: load older messages');

      if (!host.mounted) {
        return;
      }

      host.updateView(() {
        if (snapshot.docs.isNotEmpty) {
          host.stateOldestLoadedGlobalMessageDoc = snapshot.docs.last;
          mergeGlobalMessages(snapshot.docs);
        }
        host.stateHasMoreOlderGlobalMessages =
            snapshot.docs.length >= activeGlobalChatQueryPageSize;
        host.stateIsLoadingOlderGlobalMessages = false;
      });
    } catch (error, stack) {
      debugPrint('Older global chat messages could not load: $error');
      debugPrint('$stack');
      if (host.mounted) {
        host.updateView(() => host.stateIsLoadingOlderGlobalMessages = false);
      }
    }
  }

  @override
  bool isNearLatestGlobalMessage() {
    if (!host.globalChatScrollController.hasClients) {
      return true;
    }

    final position = host.globalChatScrollController.position;
    return position.pixels - position.minScrollExtent < 140;
  }

  @override
  void scheduleGlobalChatScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted || !host.globalChatScrollController.hasClients) {
        return;
      }

      host.globalChatScrollController.jumpTo(
        host.globalChatScrollController.position.minScrollExtent,
      );
    });
  }

  @override
  Future<void> confirmDeleteGlobalMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final data = doc.data();
    final mine = stringFromFirebase(data['userId'], '') == firebaseUser?.uid;

    if ((!mine && !canModerateGlobalChat) || host.isSending) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: viewContext,
      builder: (dialogContext) {
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
            trText('This message will be removed from global chat.'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: CcsText(trText('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
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

    if (shouldDelete != true) {
      return;
    }

    try {
      await globalChatCollection
          .doc(doc.id)
          .debugDelete('global chat: moderator delete message');
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
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
  Future<void> reactToGlobalMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    String? preferredEmoji,
  }) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canPostInSelectedCommunity) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    if (uid.trim().isEmpty) return;

    final reactions = messageReactionsFromFirebase(doc.data()['reactions']);
    final currentEmoji = reactions[uid] ?? '';
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
      await globalChatCollection.doc(doc.id).debugUpdate({
        'reactions.$uid': selected.trim().isEmpty
            ? FieldValue.delete()
            : selected.trim(),
      }, 'global chat: react to message');
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
  Future<void> showGlobalMessageActions(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final data = doc.data();
    final mine = stringFromFirebase(data['userId'], '') == firebaseUser?.uid;
    final canDelete = mine || canModerateGlobalChat;
    if (!canPostInSelectedCommunity && !canDelete) return;

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
                if (canPostInSelectedCommunity) ...[
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
                    leading: const Icon(
                      Icons.add_reaction_outlined,
                      color: blue,
                    ),
                    title: CcsText(
                      trText('React'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'react'),
                  ),
                ],
                if (mine)
                  ListTile(
                    leading: const Icon(Icons.edit, color: blue),
                    title: CcsText(
                      trText('Edit message'),
                      style: const TextStyle(
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
                    title: CcsText(
                      trText('Delete message'),
                      style: const TextStyle(
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
      host.updateView(() => host.replyingToGlobalMessage = doc);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if ((host.mounted && viewContext.mounted)) {
          host.messageFocusNode.requestFocus();
        }
      });
    } else if (action == 'react') {
      await reactToGlobalMessage(doc);
    } else if (action == 'edit') {
      await showEditGlobalMessageDialog(doc);
    } else if (action == 'delete') {
      await confirmDeleteGlobalMessage(doc);
    }
  }

  @override
  Future<void> showEditGlobalMessageDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final data = doc.data();
    final originalText = stringFromFirebase(data['text'], '');
    final controller = TextEditingController(text: originalText);

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
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: trText('Message in global chat'),
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
        updatedText.trim() == originalText.trim()) {
      return;
    }

    final cleanText = updatedText.trim();
    if (cleanText.isEmpty) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            trText('Message cannot be empty.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    try {
      await globalChatCollection
          .doc(doc.id)
          .debugSet(
            {
              'text': cleanText,
              'edited': true,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
            'global chat: edit own message',
          );
      unawaited(
        sendPushNotificationEvent({
          'type': 'global_chat_message',
          'messageId': doc.id,
          'mentionsOnly': true,
        }),
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
  Future<void> attachPhoto() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null ||
        host.isSending ||
        host.isUploadingPhotoAttachment) {
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
      if ((host.mounted && viewContext.mounted)) {
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
      }
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isUploadingPhotoAttachment = false);
      }
    }
  }

  @override
  Duration localGlobalChatSendCooldownRemaining() {
    final lastSentAtMillis = host.stateLastGlobalChatMessageSentAtMillis;
    if (lastSentAtMillis == null) {
      return Duration.zero;
    }

    final elapsedMillis =
        DateTime.now().millisecondsSinceEpoch - lastSentAtMillis;
    final remainingMillis =
        globalChatMessageSendCooldown.inMilliseconds - elapsedMillis;
    return remainingMillis > 0
        ? Duration(milliseconds: remainingMillis)
        : Duration.zero;
  }

  @override
  void showGlobalChatSpamWarning(Duration remaining) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    final seconds = math.max(1, (remaining.inMilliseconds / 1000).ceil());
    final message = switch (appUiPreferences.language) {
      AppLanguage.ru =>
        'Не спамьте в глобальном чате. Следующее сообщение можно отправить через $seconds сек.',
      AppLanguage.lv =>
        'Lūdzu, nespamojiet globālajā čatā. Nākamo ziņu varēs nosūtīt pēc $seconds sek.',
      AppLanguage.en =>
        'Please do not spam the global chat. You can send another message in $seconds seconds.',
    };

    ScaffoldMessenger.of(viewContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: CcsText(
            message,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
  }

  @override
  Future<int> writeGlobalChatMessageWithCooldown({
    required User firebaseUser,
    required DocumentReference<Map<String, dynamic>> messageDoc,
    required String text,
    required String photoUrl,
    MessageReplyPreviewData? replyTo,
  }) async {
    final userRef = usersCollection().doc(firebaseUser.uid);
    final attemptAtMillis = DateTime.now().millisecondsSinceEpoch;

    return FirebaseFirestore.instance.debugRunTransaction<int>((
      transaction,
    ) async {
      final userSnapshot = await transaction.debugGet(
        userRef,
        'global chat: rate limit user read',
      );
      final userData = userSnapshot.data() ?? const <String, dynamic>{};
      final lastSentAtMillis = intFromFirebase(
        userData['globalChatLastMessageAtMillis'],
        0,
      );
      final elapsedMillis = attemptAtMillis - lastSentAtMillis;
      final remainingMillis =
          globalChatMessageSendCooldown.inMilliseconds - elapsedMillis;

      if (lastSentAtMillis > 0 && remainingMillis > 0) {
        return remainingMillis;
      }

      transaction.debugSet(
        messageDoc,
        {
          'userId': firebaseUser.uid,
          'countryCode': selectedCommunityCountryCode,
          'authorCountryCode': currentUserHomeCountryCode(),
          'country': currentUser.country.trim(),
          'username': currentUser.username.trim().isEmpty
              ? 'ccs_driver'
              : currentUser.username.trim(),
          'avatarUrl': currentUser.photoUrl ?? '',
          'text': text,
          if (photoUrl.trim().isNotEmpty) 'photoUrl': photoUrl,
          if (replyTo != null && replyTo.hasContent) ...{
            'replyToMessageId': replyTo.messageId,
            'replyToUsername': replyTo.username,
            'replyToText': replyTo.text,
            'replyToPhotoUrl': replyTo.photoUrl,
          },
          'timestamp': FieldValue.serverTimestamp(),
          'type': photoUrl.trim().isNotEmpty ? 'image' : 'text',
        },
        null,
        'global chat: send message',
      );
      transaction.debugSet(
        userRef,
        {
          'globalChatLastMessageAtMillis': attemptAtMillis,
          'globalChatLastMessageAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
        'global chat: rate limit user write',
      );

      return 0;
    });
  }

  @override
  Future<void> sendMessage() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final text = host.messageController.text.trim();
    final localPhotoPath = host.pendingPhotoAttachmentPath?.trim() ?? '';
    final hasPhoto = localPhotoPath.isNotEmpty;
    final replyDoc = host.replyingToGlobalMessage;
    final replyData = replyDoc?.data();
    final replyTo = replyDoc == null || replyData == null
        ? null
        : MessageReplyPreviewData(
            messageId: replyDoc.id,
            username: stringFromFirebase(replyData['username'], 'ccs_driver'),
            text: stringFromFirebase(replyData['text'], ''),
            photoUrl: stringFromFirebase(
              replyData['photoUrl'],
              stringFromFirebase(replyData['imageUrl'], ''),
            ),
          );

    if (firebaseUser == null ||
        (!hasPhoto && text.isEmpty) ||
        host.isSending ||
        host.isUploadingPhotoAttachment) {
      return;
    }

    if (!canPostInSelectedCommunity) {
      return;
    }

    if (!ensureCommunityProfileCountry(viewContext)) return;

    final localCooldownRemaining = localGlobalChatSendCooldownRemaining();
    if (localCooldownRemaining > Duration.zero) {
      showGlobalChatSpamWarning(localCooldownRemaining);
      return;
    }

    final doc = globalChatCollection.doc();

    host.updateView(() {
      host.isSending = true;
      host.isUploadingPhotoAttachment = hasPhoto;
    });

    try {
      String photoUrl = '';
      if (hasPhoto) {
        photoUrl = await uploadChatAttachmentPhoto(
          scope: 'global_chat',
          parentId: 'main',
          messageId: doc.id,
          localPhotoPath: localPhotoPath,
        );
      }

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      // Atomically enforce one Global-chat message per user every 30 seconds
      // and create the message. Keeping the rate-limit timestamp on the user
      // document makes the normal app flow consistent across multiple devices.
      final cooldownRemainingMillis = await writeGlobalChatMessageWithCooldown(
        firebaseUser: firebaseUser,
        messageDoc: doc,
        text: text,
        photoUrl: photoUrl,
        replyTo: replyTo,
      );
      if (cooldownRemainingMillis > 0) {
        showGlobalChatSpamWarning(
          Duration(milliseconds: cooldownRemainingMillis),
        );
        return;
      }
      host.stateLastGlobalChatMessageSentAtMillis =
          DateTime.now().millisecondsSinceEpoch;

      // Clear the composer only after Firestore acknowledges the write. This
      // avoids presenting a rejected local-cache write as a successful send.
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }
      host.messageController.clear();
      host.updateView(() {
        host.pendingPhotoAttachmentPath = null;
        host.replyingToGlobalMessage = null;
        host.stateScrollGlobalChatToLatestAfterSend = true;
      });

      final senderUsername = currentUser.username.trim().isEmpty
          ? 'ccs_driver'
          : currentUser.username.trim();
      final messagePreview = text.isEmpty ? trText('Photo') : text;
      unawaited(
        sendCommunityPushNotificationEvent(
          type: 'global_chat_message',
          preferenceKey: 'newMessageNotifications',
          communityCountryCode: selectedCommunityCountryCode,
          notificationId: 'global_chat_${doc.id}',
          title: 'Global chat',
          body: '@$senderUsername: $messagePreview',
          extra: {
            'messageId': doc.id,
            'senderUsername': senderUsername,
            'messageText': messagePreview,
            'countryCode': selectedCommunityCountryCode,
          },
        ),
      );

      unawaited(
        notifyStaffAboutCommunityEvent(
          type: 'global_chat_admin',
          notificationId: 'global_chat_admin_${doc.id}',
          title: 'New global chat message',
          body:
              '@${currentUser.username}: ${text.isEmpty ? trText('Photo') : text}',
          extra: {'messageId': doc.id},
          // Staff still get the moderation-center item above, but not a
          // second unthrottled push for every Global-chat message.
          sendPush: false,
        ),
      );
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
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
              isFirestorePermissionDenied(error)
                  ? 'Global chat write was blocked by Firestore rules. Allow authenticated users to create global_chat messages with their own userId and update globalChatLastMessageAtMillis/globalChatLastMessageAt on their own user document.'
                  : hasPhoto
                  ? 'Could not attach photo: $error'
                  : 'Could not send message: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() {
          host.isSending = false;
          host.isUploadingPhotoAttachment = false;
        });
      }
    }
  }

  @override
  List<Widget> globalChatMessageList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  ) {
    final widgets = <Widget>[];
    String previousLabel = '';
    String previousSenderUid = '';

    for (final doc in messages) {
      final data = doc.data();
      final createdAtMillis = timestampMillisFromFirebase(data['timestamp']);
      final label = chatDateDividerLabel(createdAtMillis);

      if (label.isNotEmpty && label != previousLabel) {
        widgets.add(chatDateDivider(label));
        previousLabel = label;
        previousSenderUid = '';
      }

      final senderUid = stringFromFirebase(data['userId'], '');
      final showAuthorHeader =
          senderUid.isEmpty || senderUid != previousSenderUid;
      widgets.add(
        host.content.messageBubble(doc, showAuthorHeader: showAuthorHeader),
      );
      previousSenderUid = senderUid;
    }

    return widgets;
  }
}
