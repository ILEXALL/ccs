import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserHomeCountryCode;
import 'package:ccs_app/features/community/chats/data/chat_photos.dart'
    show uploadChatAttachmentPhoto;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData, messageReactionsFromFirebase;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show showEmojiReactionPicker;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityContentCountryCode, ensureCommunityProfileCountry;
import 'package:ccs_app/features/community/forum/data/forum_reply_counts.dart'
    show invalidateForumReplyCount;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show groupForumAccessible;
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/community/forum/screens/edit_forum_topic.dart'
    show EditForumTopicPage;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry, currentUserHasCommunityModerationAccess;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show inAppBadges;
import 'package:ccs_app/features/notifications/data/community_notifications.dart'
    show sendCommunityPushNotificationEvent;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show sendPushNotificationEvent;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/countries.dart' show countryNamesByIso;
import 'package:ccs_app/shared/models/user_role.dart' show roleName;
import 'package:ccs_app/features/community/forum/controllers/forum_topic_view_state.dart';

/// Coordinates actions and data loading for ForumTopicPage.
class ForumTopicController implements ForumTopicControllerActions {
  final ForumTopicViewState host;
  ForumTopicController(this.host);

  @override
  bool get isReadingTopic =>
      host.mounted &&
      ModalRoute.of(host.context)?.isCurrent == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void markLoadedRepliesRead(String countryCode) {
    if (!host.stateHasLoadedReplies) return;
    // Notify badge widgets after this frame has rendered the replies.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isReadingTopic) return;
      inAppBadges.openForumTopic(
        host.widget.topicId,
        countryCode,
        latestReplyAtMillis: host.stateLatestLoadedReplyAtMillis,
        isVisible: () => isReadingTopic,
      );
    });
  }

  @override
  DocumentReference<Map<String, dynamic>> get topicDocument => FirebaseFirestore
      .instance
      .collection('forum_topics')
      .doc(host.widget.topicId);

  @override
  CollectionReference<Map<String, dynamic>> get topicRepliesCollection =>
      topicDocument.collection('replies');

  @override
  bool get canModerateForumTopic =>
      host.stateTopicCountryResolved &&
      currentUserCanModerateCountry(
        host.stateTopicCountryCode,
        community: true,
      );

  @override
  void groupMembershipChanged() {
    if (host.mounted) host.updateView(() {});
  }

  @override
  bool get canPostInForumTopic =>
      (host.stateResolvedTopic == null ||
          groupForumAccessible(host.stateResolvedTopic!)) &&
      (!host.stateTopicCountryResolved ||
          countryNamesByIso.containsKey(host.stateTopicCountryCode));

  @override
  Future<void> loadCommunityModerationAccess() async {
    await currentUserHasCommunityModerationAccess();
    if (host.mounted) {
      host.updateView(() {});
    }
  }

  @override
  Future<void> attachPhoto({bool useCamera = false}) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null ||
        host.isSending ||
        host.isUploadingPhotoAttachment) {
      return;
    }

    host.updateView(() => host.isUploadingPhotoAttachment = true);

    var captured = false;
    try {
      final path = await pickPhotoFromPhone(
        viewContext,
        cropPhoto: false,
        useCamera: useCamera,
      );

      if (!(host.mounted && viewContext.mounted) ||
          path == null ||
          path.trim().isEmpty) {
        return;
      }

      host.updateView(() => host.pendingPhotoAttachmentPath = path);
      captured = useCamera;
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
    if (captured && host.mounted) await sendReply();
  }

  @override
  Future<void> sendReply() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!ensureCommunityProfileCountry(viewContext)) return;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final text = host.replyController.text.trim();
    final localPhotoPath = host.pendingPhotoAttachmentPath?.trim() ?? '';
    final hasPhoto = localPhotoPath.isNotEmpty;
    final replyDoc = host.replyingToForumReply;
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

    final topicSnapshot = await topicDocument.debugGet(
      null,
      'forum: verify regional reply access',
    );
    final topicData = topicSnapshot.data();
    if (topicData == null) {
      return;
    }
    host.stateTopicCountryCode = communityContentCountryCode(topicData);

    final doc = topicRepliesCollection.doc();

    host.updateView(() {
      host.isSending = true;
      host.isUploadingPhotoAttachment = hasPhoto;
    });

    try {
      String photoUrl = '';
      if (hasPhoto) {
        photoUrl = await uploadChatAttachmentPhoto(
          scope: 'forum_topics',
          parentId: host.widget.topicId,
          messageId: doc.id,
          localPhotoPath: localPhotoPath,
        );
      }

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.replyController.clear();
      host.updateView(() {
        host.pendingPhotoAttachmentPath = null;
        host.replyingToForumReply = null;
      });

      await doc.debugSet(
        {
          'userId': firebaseUser.uid,
          'countryCode': host.stateTopicCountryCode,
          'authorCountryCode': currentUserHomeCountryCode(),
          'country': currentUser.country.trim(),
          'username': currentUser.username,
          'avatarUrl': currentUser.photoUrl ?? '',
          'role': roleName(currentUser.role),
          'verified': currentUser.verified,
          'globalChatModerator': currentUser.globalChatModerator,
          'globalModerator': currentUser.globalChatModerator,
          'text': text,
          if (photoUrl.trim().isNotEmpty) 'photoUrl': photoUrl,
          if (replyTo != null && replyTo.hasContent) ...{
            'replyToMessageId': replyTo.messageId,
            'replyToUsername': replyTo.username,
            'replyToText': replyTo.text,
            'replyToPhotoUrl': replyTo.photoUrl,
          },
          if (photoUrl.trim().isNotEmpty) 'type': 'image',
          'timestamp': FieldValue.serverTimestamp(),
        },
        null,
        'forum: send reply',
      );

      await topicDocument.debugSet({
        'repliesCount': FieldValue.increment(1),
        'lastReplyAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      invalidateForumReplyCount(host.widget.topicId);
      forumTopicsRefreshTick.value++;

      final senderUsername = currentUser.username.trim().isEmpty
          ? 'ccs_driver'
          : currentUser.username.trim();
      final messagePreview = text.isEmpty ? trText('Photo') : text;
      unawaited(
        sendCommunityPushNotificationEvent(
          type: 'forum_reply',
          // The settings screen describes this switch as covering community
          // replies, while the Messages switch is for chat conversations.
          preferenceKey: 'commentNotifications',
          communityCountryCode: host.stateTopicCountryCode,
          notificationId: 'forum_${host.widget.topicId}_${doc.id}',
          title: host.widget.title.trim().isEmpty
              ? 'Forum'
              : 'Forum • ${host.widget.title.trim()}',
          body: '@$senderUsername: $messagePreview',
          extra: {
            'topicId': host.widget.topicId,
            'topicTitle': host.widget.title,
            'messageId': doc.id,
            'senderUsername': senderUsername,
            'messageText': messagePreview,
            'countryCode': host.stateTopicCountryCode,
          },
        ),
      );
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        if (host.replyController.text.trim().isEmpty) {
          host.replyController.text = text;
          host.replyController.selection = TextSelection.collapsed(
            offset: host.replyController.text.length,
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
  Future<void> toggleTopicPinned(bool isPinned) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canModerateForumTopic) {
      return;
    }

    try {
      await topicDocument.debugSet({
        'isPinned': !isPinned,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not update topic')}: $error',
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
  Future<void> editTopicHeader(Map<String, dynamic> topic) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    await Navigator.push(
      viewContext,
      appPageRoute(
        builder: (_) => EditForumTopicPage(
          topicId: host.widget.topicId,
          initialTitle: stringFromFirebase(topic['title'], host.widget.title),
          initialDescription: stringFromFirebase(topic['description'], ''),
        ),
      ),
    );
  }

  @override
  Future<void> deleteTopic() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final shouldDelete = await showDialog<bool>(
      context: viewContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(
            trText('Delete topic?'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: CcsText(
            trText(
              'The topic header and discussion will be removed from the forum.',
            ),
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
      await topicDocument.debugDelete('forum: delete topic');
      forumTopicsRefreshTick.value++;
      if ((host.mounted && viewContext.mounted)) {
        Navigator.pop(viewContext);
      }
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not delete topic')}: $error',
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
  Future<void> confirmDeleteForumReply(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final data = doc.data();
    final mine = stringFromFirebase(data['userId'], '') == firebaseUser?.uid;

    if (!mine && !canModerateForumTopic) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: viewContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(
            trText('Delete reply?'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: CcsText(
            trText('This reply will be removed from the topic.'),
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
      await topicRepliesCollection
          .doc(doc.id)
          .debugDelete('forum: delete reply');
      try {
        await topicDocument.debugSet({
          'repliesCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (error, stack) {
        debugPrint(
          'Forum topic count update skipped after reply delete: $error',
        );
        debugPrint('$stack');
      }

      invalidateForumReplyCount(host.widget.topicId);
      forumTopicsRefreshTick.value++;
    } catch (error) {
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not delete reply')}: $error',
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
  Future<void> reactToForumReply(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    String? preferredEmoji,
  }) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (!canPostInForumTopic) return;
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
      await topicRepliesCollection.doc(doc.id).debugUpdate({
        'reactions.$uid': selected.trim().isEmpty
            ? FieldValue.delete()
            : selected.trim(),
      }, 'forum: react to reply');
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
  Future<void> showForumReplyActions(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final data = doc.data();
    final mine = stringFromFirebase(data['userId'], '') == firebaseUser?.uid;
    final canDelete = mine || canModerateForumTopic;
    if (!canPostInForumTopic && !canDelete) return;

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
                if (canPostInForumTopic) ...[
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
      host.updateView(() => host.replyingToForumReply = doc);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if ((host.mounted && viewContext.mounted)) {
          host.replyFocusNode.requestFocus();
        }
      });
    } else if (action == 'react') {
      await reactToForumReply(doc);
    } else if (action == 'edit') {
      await showEditForumReplyDialog(doc);
    } else if (action == 'delete') {
      await confirmDeleteForumReply(doc);
    }
  }

  @override
  Future<void> showEditForumReplyDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final originalText = stringFromFirebase(doc.data()['text'], '');
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
              hintText: trText('Reply in topic'),
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
      await topicRepliesCollection
          .doc(doc.id)
          .debugSet(
            {
              'text': cleanText,
              'edited': true,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
            'forum: edit own reply',
          );
      unawaited(
        sendPushNotificationEvent({
          'type': 'forum_reply',
          'topicId': host.widget.topicId,
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
}
