import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, timestampMillisFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show messageReactionsFromFirebase, messageReplyPreviewFromFirebase;
import 'package:ccs_app/features/community/chats/widgets/chat_link_text.dart'
    show ChatLinkText;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show ChatAttachmentImage;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show LiveCommunityAuthorIdentity;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show formatChatMessageTime;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show messageReactionBar, messageReplyPreviewCard;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityAuthorCountryCode, communityContentCountryCode;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/shared/models/user_role.dart'
    show roleFromFirebase, userRoleIsStaff;
import 'package:ccs_app/features/community/global_chat/controllers/global_chat_view_state.dart';

/// Renders reusable sections for GlobalChatTab.
class GlobalChatContent implements GlobalChatContentActions {
  final GlobalChatViewState host;
  GlobalChatContent(this.host);

  @override
  Widget messageBubble(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool showAuthorHeader,
  }) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final data = doc.data();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final mine = stringFromFirebase(data['userId'], '') == firebaseUser?.uid;
    final userId = stringFromFirebase(data['userId'], '');
    final username = stringFromFirebase(data['username'], 'ccs_driver');
    final avatarUrl = stringFromFirebase(data['avatarUrl'], '');
    final fallbackRole = roleFromFirebase(data['role']);
    final fallbackGlobalModerator = userDataHasCommunityModerationAccess(data);
    final fallbackVerified =
        userRoleIsStaff(fallbackRole) || data['verified'] == true;
    final edited = data['edited'] == true;
    final text = stringFromFirebase(data['text'], '');
    final photoUrl = stringFromFirebase(
      data['photoUrl'],
      stringFromFirebase(data['imageUrl'], ''),
    );
    final time = formatChatMessageTime(
      timestampMillisFromFirebase(data['timestamp']),
    );
    final replyPreview = messageReplyPreviewFromFirebase(data);
    final reactions = messageReactionsFromFirebase(data['reactions']);
    final currentUid = firebaseUser?.uid ?? currentUser.uid;
    final channelCountryCode = communityContentCountryCode(data);
    final authorCountryCode = communityAuthorCountryCode(data);
    final canActOnMessage =
        host.controller.canPostInSelectedCommunity ||
        mine ||
        host.controller.canModerateGlobalChat;

    void openAuthorProfile() {
      if (userId.trim().isEmpty) {
        return;
      }

      openUserProfile(viewContext, uid: userId, fallbackUsername: username);
    }

    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: openAuthorProfile,
            behavior: HitTestBehavior.opaque,
            child: LiveCommunityAuthorIdentity(
              uid: userId,
              fallbackAvatarUrl: avatarUrl,
              fallbackUsername: username,
              fallbackRole: fallbackRole,
              fallbackVerified: fallbackVerified,
              fallbackGlobalChatModerator: fallbackGlobalModerator,
              authorCountryCode: authorCountryCode,
              channelCountryCode: channelCountryCode,
            ),
          ),
        ),
        if (time.isNotEmpty) ...[
          const SizedBox(width: 10),
          CcsText(
            time,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );

    final card = IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 54, maxWidth: 292),
        child: Container(
          padding: EdgeInsets.fromLTRB(11, showAuthorHeader ? 10 : 8, 11, 8),
          decoration: BoxDecoration(
            color: mine ? blue : const Color(0xFF171717),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(showAuthorHeader || mine ? 16 : 6),
              topRight: Radius.circular(showAuthorHeader || !mine ? 16 : 6),
              bottomLeft: const Radius.circular(16),
              bottomRight: const Radius.circular(16),
            ),
            border: Border.all(
              color: mine
                  ? blue.withValues(alpha: 0.9)
                  : const Color(0xFF2A2A2A),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthorHeader) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: header,
                ),
                const SizedBox(height: 7),
              ],
              if (replyPreview.hasContent) ...[
                messageReplyPreviewCard(replyPreview),
                const SizedBox(height: 8),
              ],
              if (photoUrl.trim().isNotEmpty) ...[
                ChatAttachmentImage(imageUrl: photoUrl, mine: mine),
                if (text.trim().isNotEmpty) const SizedBox(height: 8),
              ],
              if (text.trim().isNotEmpty)
                ChatLinkText(
                  text,
                  linkColor: mine ? const Color(0xFFFFF3B0) : blue,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.25,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (edited ||
                  (!showAuthorHeader && time.isNotEmpty) ||
                  canActOnMessage) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (edited) ...[
                      CcsText(
                        trText('edited'),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!showAuthorHeader && time.isNotEmpty)
                        const SizedBox(width: 6),
                    ],
                    if (!showAuthorHeader && time.isNotEmpty)
                      CcsText(
                        time,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                        ),
                      ),
                    if (canActOnMessage) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () =>
                            host.controller.showGlobalMessageActions(doc),
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
              ],
              messageReactionBar(
                reactions: reactions,
                currentUid: currentUid,
                onEmojiTap: host.controller.canPostInSelectedCommunity
                    ? (emoji) => unawaited(
                        host.controller.reactToGlobalMessage(
                          doc,
                          preferredEmoji: emoji,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );

    final interactiveCard = canActOnMessage
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => host.controller.showGlobalMessageActions(doc),
            onLongPress: () => host.controller.showGlobalMessageActions(doc),
            child: card,
          )
        : card;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: mine ? 46 : 0,
          right: mine ? 0 : 46,
          bottom: showAuthorHeader ? 8 : 4,
        ),
        child: interactiveCard,
      ),
    );
  }
}
