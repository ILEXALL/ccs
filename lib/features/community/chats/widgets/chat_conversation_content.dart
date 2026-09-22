import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/collections.dart'
    show userPresenceDocument, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/chat_message.dart'
    show ChatMessageData;
import 'package:ccs_app/features/community/chats/widgets/chat_link_text.dart'
    show ChatLinkText;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show ChatAttachmentImage;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show ChatTitleAvatar, formatChatMessageTime;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show messageReactionBar, messageReplyPreviewCard;
import 'package:ccs_app/features/community/chats/widgets/message_status.dart'
    show ChatMessageStatusGlyph;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateCountry;
import 'package:ccs_app/shared/widgets/user_avatar.dart'
    show
        OnlineStatusBadge,
        UserAvatarCircle,
        fallbackChatMember,
        fallbackMessageSender,
        friendUserFromSnapshot;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;
import 'package:ccs_app/features/community/chats/controllers/chat_conversation_view_state.dart';

/// Renders reusable sections for ChatConversationScreen.
class ChatConversationContent implements ChatConversationContentActions {
  final ChatConversationViewState host;
  ChatConversationContent(this.host);

  @override
  Widget directChatTitle(
    String currentUid,
    String fallbackTitle,
    String fallbackPhotoUrl,
  ) {
    final uid = host.controller.otherUserId(currentUid);

    Widget titleContent(FriendUserData? user) {
      final title = user == null
          ? fallbackTitle
          : displayUsername(user.username);

      return InkWell(
        onTap: () => host.controller.openChatUserProfile(currentUid),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              user == null
                  ? ChatTitleAvatar(photoUrl: fallbackPhotoUrl, title: title)
                  : UserAvatarCircle(user: user, size: 34),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: CcsText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (user != null) ...[
                          const SizedBox(width: 4),
                          UserPrimaryBadge(
                            role: user.role,
                            verified: user.verified,
                            globalChatModerator: user.globalChatModerator,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    OnlineStatusBadge(
                      online: user?.appearsOnline ?? false,
                      dotSize: 6,
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (uid == null) {
      return titleContent(null);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCollection()
          .doc(uid)
          .debugSnapshots('chat: conversation title user listener'),
      builder: (context, snapshot) {
        final user =
            friendUserFromSnapshot(snapshot.data) ??
            fallbackChatMember(host.widget.chat, uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userPresenceDocument(
            uid,
          ).debugSnapshots('chat: conversation title presence listener'),
          builder: (context, presenceSnapshot) {
            return titleContent(
              user.withPresenceFromMap(presenceSnapshot.data?.data()),
            );
          },
        );
      },
    );
  }

  @override
  Widget groupChatTitle(String title) {
    return InkWell(
      onTap: host.controller.readOnly
          ? null
          : host.controller.openGroupSettings,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups, size: 21),
            const SizedBox(width: 8),
            Flexible(
              child: CcsText(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget messageBubble(
    ChatMessageData message,
    String currentUid,
    Map<String, FriendUserData> usersById, {
    required bool showAuthorHeader,
  }) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final mine = message.senderUid == currentUid;
    final canDeleteMessage =
        host.widget.chat.isGroup &&
        (currentUserCanModerateCountry(
              host.widget.chat.countryCode,
              community: true,
            ) ||
            host.widget.chat.ownerUid == currentUid ||
            host.widget.chat.moderatorIds.contains(currentUid));
    final canActOnMessage =
        !host.controller.readOnly && !message.isLocalPending;
    final sender =
        usersById[message.senderUid] ?? fallbackMessageSender(message);
    final receiptState = mine
        ? message.receiptStateFor(host.widget.chat, currentUid)
        : null;

    void openSenderProfile() {
      openUserProfile(
        viewContext,
        uid: sender.uid,
        fallbackUsername: sender.username,
      );
    }

    Widget senderIdentity() {
      return GestureDetector(
        onTap: openSenderProfile,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatarCircle(user: sender, size: 30),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: CcsText(
                      displayUsername(sender.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  UserPrimaryBadge(
                    role: sender.role,
                    verified: sender.verified,
                    globalChatModerator: sender.globalChatModerator,
                    compact: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            CcsText(
              formatChatMessageTime(message.createdAtMillis),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final card = IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 58, maxWidth: 292),
        child: Container(
          padding: EdgeInsets.fromLTRB(11, showAuthorHeader ? 10 : 8, 11, 8),
          decoration: BoxDecoration(
            color: mine
                ? (message.sendFailed
                      ? Colors.redAccent.withValues(alpha: 0.82)
                      : blue)
                : panel,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(showAuthorHeader || mine ? 16 : 6),
              topRight: Radius.circular(showAuthorHeader || !mine ? 16 : 6),
              bottomLeft: const Radius.circular(16),
              bottomRight: const Radius.circular(16),
            ),
            border: mine ? null : Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAuthorHeader) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: senderIdentity(),
                ),
                const SizedBox(height: 7),
              ],
              if (message.replyPreview.hasContent) ...[
                messageReplyPreviewCard(message.replyPreview),
                const SizedBox(height: 8),
              ],
              if (message.photoUrl.trim().isNotEmpty) ...[
                ChatAttachmentImage(imageUrl: message.photoUrl, mine: mine),
                if (message.text.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (message.text.trim().isNotEmpty)
                ChatLinkText(
                  message.text,
                  linkColor: mine ? const Color(0xFFFFF3B0) : blue,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    shadows: message.isLocalPending
                        ? [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              offset: const Offset(0, 1),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.edited) ...[
                    CcsText(
                      trText('edited'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (!showAuthorHeader)
                    CcsText(
                      formatChatMessageTime(message.createdAtMillis),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (receiptState != null) ...[
                    if (!showAuthorHeader) const SizedBox(width: 6),
                    ChatMessageStatusGlyph(state: receiptState),
                  ],
                  if (canActOnMessage) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () =>
                          host.controller.showOwnMessageActions(message),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        child: Icon(
                          Icons.more_horiz,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!host.controller.readOnly)
                messageReactionBar(
                  reactions: message.reactions,
                  currentUid: currentUid,
                  onEmojiTap: (emoji) => unawaited(
                    host.controller.reactToChatMessage(
                      message,
                      preferredEmoji: emoji,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final interactiveCard = canActOnMessage
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => host.controller.showOwnMessageActions(message),
            onLongPress: () => host.controller.showOwnMessageActions(message),
            child: card,
          )
        : card;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: mine ? 44 : 0,
          right: mine ? 0 : 44,
          bottom: showAuthorHeader ? 8 : 4,
        ),
        child: interactiveCard,
      ),
    );
  }
}
