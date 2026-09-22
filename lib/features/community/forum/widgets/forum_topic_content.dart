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
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show messageReactionsFromFirebase, messageReplyPreviewFromFirebase;
import 'package:ccs_app/features/community/chats/widgets/chat_link_text.dart'
    show ChatLinkText;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show ChatAttachmentImage;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show GlobalSmallAvatar;
import 'package:ccs_app/features/community/chats/widgets/chat_title_avatar.dart'
    show formatChatMessageTime;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show messageReactionBar, messageReplyPreviewCard;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityAuthorCountryCode, communityContentCountryCode;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show forumTopicPhotos, groupForumAccessible;
import 'package:ccs_app/features/community/widgets/country_selector.dart'
    show CommunityAvatarWithCountryFlag;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/features/spots/widgets/spot_info_tag.dart'
    show SpotInfoTag;
import 'package:ccs_app/shared/media/photo_gallery.dart' show SpotPhotoCarousel;
import 'package:ccs_app/shared/models/user_role.dart'
    show roleFromFirebase, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/user_badge.dart'
    show UserPrimaryBadgeForUid;
import 'package:ccs_app/features/community/forum/controllers/forum_topic_view_state.dart';

/// Renders reusable sections for ForumTopicPage.
class ForumTopicContent implements ForumTopicContentActions {
  final ForumTopicViewState host;
  ForumTopicContent(this.host);

  @override
  Widget topicHeader(Map<String, dynamic> topic) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
    final authorId = stringFromFirebase(topic['authorId'], '');
    final authorName = stringFromFirebase(topic['authorName'], 'ccs_driver');
    final avatarUrl = stringFromFirebase(topic['avatarUrl'], '');
    final description = stringFromFirebase(topic['description'], '');
    if (!groupForumAccessible(topic))
      return CcsText(trText('This topic is available only to group members.'));
    final photos = forumTopicPhotos(topic);
    final fallbackRole = roleFromFirebase(topic['authorRole'] ?? topic['role']);
    final fallbackGlobalModerator =
        topic['authorGlobalChatModerator'] == true ||
        topic['authorGlobalModerator'] == true ||
        userDataHasCommunityModerationAccess(topic);
    final fallbackVerified =
        userRoleIsStaff(fallbackRole) || topic['authorVerified'] == true;
    final createdAt = formatChatMessageTime(
      timestampMillisFromFirebase(topic['createdAt']),
    );
    final channelCountryCode = communityContentCountryCode(topic);
    final authorCountryCode = communityAuthorCountryCode(topic);
    final canEditHeader =
        host.controller.canModerateForumTopic ||
        (host.controller.canPostInForumTopic &&
            authorId.isNotEmpty &&
            authorId == currentUid);
    final canDeleteHeader = canEditHeader;

    void openTopicAuthorProfile() {
      if (authorId.trim().isEmpty) {
        return;
      }

      openUserProfile(viewContext, uid: authorId, fallbackUsername: authorName);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blue.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openTopicAuthorProfile,
            behavior: HitTestBehavior.opaque,
            child: CommunityAvatarWithCountryFlag(
              authorCountryCode: authorCountryCode,
              channelCountryCode: channelCountryCode,
              avatar: GlobalSmallAvatar(
                avatarUrl: avatarUrl,
                username: authorName,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: openTopicAuthorProfile,
                        behavior: HitTestBehavior.opaque,
                        child: CcsText(
                          displayUsername(authorName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    UserPrimaryBadgeForUid(
                      uid: authorId,
                      fallbackRole: fallbackRole,
                      fallbackVerified: fallbackVerified,
                      fallbackGlobalChatModerator: fallbackGlobalModerator,
                      compact: true,
                    ),
                    if (createdAt.isNotEmpty) ...[
                      const Spacer(),
                      CcsText(
                        createdAt,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    SpotInfoTag(
                      label: trText('Topic creator'),
                      icon: Icons.edit_note_rounded,
                    ),
                  ],
                ),
                if (description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  CcsText(
                    description,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SpotPhotoCarousel.photos(
                      key: ValueKey(photos.join('|')),
                      sources: photos,
                      height: 220,
                    ),
                  ),
                ],
                if (host.controller.canModerateForumTopic || canEditHeader) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canEditHeader)
                        OutlinedButton.icon(
                          onPressed: () =>
                              host.controller.editTopicHeader(topic),
                          icon: const Icon(Icons.edit, size: 18),
                          label: CcsText(trText('Edit')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: blue,
                            side: const BorderSide(color: blue),
                          ),
                        ),
                      if (canDeleteHeader)
                        OutlinedButton.icon(
                          onPressed: host.controller.deleteTopic,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: CcsText(trText('Delete')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget replyTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool showAuthorHeader,
  }) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final data = doc.data();
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
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
    final authorCountryCode = communityAuthorCountryCode(data);
    final mine = userId == currentUid;
    final canActOnReply =
        host.controller.canPostInForumTopic ||
        mine ||
        host.controller.canModerateForumTopic;

    void openReplyAuthorProfile() {
      if (userId.trim().isEmpty) {
        return;
      }

      openUserProfile(viewContext, uid: userId, fallbackUsername: username);
    }

    final header = GestureDetector(
      onTap: openReplyAuthorProfile,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CommunityAvatarWithCountryFlag(
            authorCountryCode: authorCountryCode,
            channelCountryCode: host.stateTopicCountryCode,
            avatar: GlobalSmallAvatar(avatarUrl: avatarUrl, username: username),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: CcsText(
                    displayUsername(username),
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
                UserPrimaryBadgeForUid(
                  uid: userId,
                  fallbackRole: fallbackRole,
                  fallbackVerified: fallbackVerified,
                  fallbackGlobalChatModerator: fallbackGlobalModerator,
                  compact: true,
                ),
              ],
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 10),
            CcsText(
              time,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );

    final tile = Container(
      margin: EdgeInsets.only(bottom: showAuthorHeader ? 8 : 4),
      padding: EdgeInsets.fromLTRB(12, showAuthorHeader ? 10 : 8, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(showAuthorHeader ? 15 : 6),
          topRight: const Radius.circular(15),
          bottomLeft: const Radius.circular(15),
          bottomRight: const Radius.circular(15),
        ),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
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
              child: header,
            ),
            const SizedBox(height: 8),
          ],
          if (replyPreview.hasContent) ...[
            messageReplyPreviewCard(replyPreview),
            const SizedBox(height: 8),
          ],
          if (photoUrl.trim().isNotEmpty) ...[
            ChatAttachmentImage(imageUrl: photoUrl),
            if (text.trim().isNotEmpty) const SizedBox(height: 8),
          ],
          if (text.trim().isNotEmpty)
            ChatLinkText(
              text,
              linkColor: mine ? const Color(0xFFFFF3B0) : blue,
              style: const TextStyle(
                color: Colors.white,
                height: 1.32,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (edited ||
              (!showAuthorHeader && time.isNotEmpty) ||
              canActOnReply) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited) ...[
                  CcsText(
                    trText('edited'),
                    style: const TextStyle(
                      color: Colors.white38,
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
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                if (canActOnReply) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => host.controller.showForumReplyActions(doc),
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
            onEmojiTap: host.controller.canPostInForumTopic
                ? (emoji) => unawaited(
                    host.controller.reactToForumReply(
                      doc,
                      preferredEmoji: emoji,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );

    if (!canActOnReply) {
      return tile;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => host.controller.showForumReplyActions(doc),
      onLongPress: () => host.controller.showForumReplyActions(doc),
      child: tile,
    );
  }
}
