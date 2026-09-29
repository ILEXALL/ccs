import 'package:ccs_app/features/community/forum/controllers/forum_topic_view_state.dart';
import 'package:ccs_app/features/community/forum/widgets/forum_topic_content.dart';
import 'package:ccs_app/features/community/forum/controllers/forum_topic_controller.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension, FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/community/chats/models/message_reply.dart'
    show MessageReplyPreviewData;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show stagedChatPhotoPreview;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/chats/widgets/message_reactions.dart'
    show messageReplyPreviewCard;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityContentCountryCode, communityText;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show groupForumAccessible;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show memberSpotGroups;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show inAppBadges;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class ForumTopicPage extends StatefulWidget implements ForumTopicInputs {
  @override
  final String topicId;
  @override
  final String title;
  @override
  final String countryCode;

  const ForumTopicPage({
    super.key,
    required this.topicId,
    required this.title,
    this.countryCode = '',
  });

  @override
  State<ForumTopicPage> createState() => _ForumTopicPageState();
}

class _ForumTopicPageState extends State<ForumTopicPage>
    with LanguageReactiveState, WidgetsBindingObserver
    implements ForumTopicViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> get stateTopicStream =>
      _topicStream;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> get stateRepliesStream =>
      _repliesStream;

  @override
  String get stateTopicCountryCode => _topicCountryCode;

  @override
  set stateTopicCountryCode(String value) => _topicCountryCode = value;

  @override
  bool get stateTopicCountryResolved => _topicCountryResolved;

  @override
  set stateTopicCountryResolved(bool value) => _topicCountryResolved = value;

  @override
  bool get stateHasLoadedReplies => _hasLoadedReplies;

  @override
  set stateHasLoadedReplies(bool value) => _hasLoadedReplies = value;

  @override
  int? get stateLatestLoadedReplyAtMillis => _latestLoadedReplyAtMillis;

  @override
  set stateLatestLoadedReplyAtMillis(int? value) =>
      _latestLoadedReplyAtMillis = value;

  @override
  Map<String, dynamic>? get stateResolvedTopic => _resolvedTopic;

  @override
  set stateResolvedTopic(Map<String, dynamic>? value) => _resolvedTopic = value;

  @override
  late final ForumTopicContentActions content = ForumTopicContent(this);

  @override
  late final ForumTopicControllerActions controller = ForumTopicController(
    this,
  );

  @override
  final replyController = TextEditingController();
  @override
  final replyFocusNode = FocusNode();
  @override
  final topicScrollController = ScrollController();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _topicStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _repliesStream;
  @override
  bool isSending = false;
  @override
  bool isUploadingPhotoAttachment = false;
  @override
  String? pendingPhotoAttachmentPath;
  @override
  QueryDocumentSnapshot<Map<String, dynamic>>? replyingToForumReply;
  late String _topicCountryCode;
  late bool _topicCountryResolved;
  bool _hasLoadedReplies = false;
  int? _latestLoadedReplyAtMillis;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _topicCountryResolved) {
      controller.markLoadedRepliesRead(_topicCountryCode);
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Map<String, dynamic>? _resolvedTopic;

  @override
  void initState() {
    super.initState();
    memberSpotGroups.addListener(controller.groupMembershipChanged);
    _topicCountryCode = widget.countryCode.trim().toUpperCase();
    _topicCountryResolved = _topicCountryCode.isNotEmpty;
    _topicStream = controller.topicDocument.debugSnapshots(
      'forum: topic listener',
    );
    _repliesStream = controller.topicRepliesCollection
        .orderBy('timestamp', descending: true)
        .limit(50)
        .debugSnapshots('forum: topic replies listener');
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.loadCommunityModerationAccess());
  }

  @override
  void dispose() {
    memberSpotGroups.removeListener(controller.groupMembershipChanged);
    WidgetsBinding.instance.removeObserver(this);
    inAppBadges.closeForumTopic(widget.topicId);
    topicScrollController.dispose();
    replyFocusNode.dispose();
    replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: CcsText(widget.title),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _topicStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: blue),
                    );
                  }

                  final topic = snapshot.data?.data();
                  _resolvedTopic = topic;
                  if (snapshot.hasError ||
                      (topic != null && !groupForumAccessible(topic))) {
                    return Center(
                      child: CcsText(
                        trText(
                          'This topic is available only to group members.',
                        ),
                      ),
                    );
                  }
                  if (topic == null) {
                    return EmptyStateCard(
                      icon: Icons.forum_outlined,
                      title: trText('Topic not found'),
                      text: trText('This topic may have been removed.'),
                    );
                  }

                  final resolvedCountryCode = communityContentCountryCode(
                    topic,
                  );
                  if (!_topicCountryResolved ||
                      _topicCountryCode != resolvedCountryCode) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _topicCountryCode = resolvedCountryCode;
                        _topicCountryResolved = true;
                      });
                    });
                  }

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _repliesStream,
                    builder: (context, repliesSnapshot) {
                      if (repliesSnapshot.hasData &&
                          !repliesSnapshot.hasError) {
                        // Cached replies are readable too; an unchanged server
                        // result may never trigger another stream event.
                        _hasLoadedReplies = true;
                        for (final reply in repliesSnapshot.data!.docs) {
                          final stamp = reply.data()['timestamp'];
                          if (stamp is Timestamp &&
                              stamp.millisecondsSinceEpoch >
                                  (_latestLoadedReplyAtMillis ?? 0)) {
                            _latestLoadedReplyAtMillis =
                                stamp.millisecondsSinceEpoch;
                          }
                        }
                        controller.markLoadedRepliesRead(resolvedCountryCode);
                      }
                      final replies =
                          repliesSnapshot.data?.docs.reversed.toList() ??
                          const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                      return ListView(
                        controller: topicScrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                        children: [
                          content.topicHeader(topic),
                          if (repliesSnapshot.connectionState ==
                              ConnectionState.waiting)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: CircularProgressIndicator(color: blue),
                              ),
                            )
                          else if (replies.isEmpty)
                            EmptyStateCard(
                              icon: Icons.forum_outlined,
                              title: trText('No replies yet'),
                              text: trText(
                                'Be the first to reply in this topic.',
                              ),
                            )
                          else
                            for (var index = 0; index < replies.length; index++)
                              content.replyTile(
                                replies[index],
                                showAuthorHeader:
                                    index == 0 ||
                                    stringFromFirebase(
                                          replies[index].data()['userId'],
                                          '',
                                        ) !=
                                        stringFromFirebase(
                                          replies[index - 1].data()['userId'],
                                          '',
                                        ),
                              ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (!controller.canPostInForumTopic)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined, color: blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CcsText(
                        communityText(
                          en: 'This country’s forum is read-only for you.',
                          ru: 'Форум этой страны доступен вам только для чтения.',
                          lv: 'Šīs valsts forums jums ir pieejams tikai lasīšanai.',
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              bottom: !keyboardOpen,
              child: Container(
                padding: EdgeInsets.fromLTRB(10, 6, 10, keyboardOpen ? 0 : 8),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replyingToForumReply != null) ...[
                      messageReplyPreviewCard(
                        MessageReplyPreviewData(
                          messageId: replyingToForumReply!.id,
                          username: stringFromFirebase(
                            replyingToForumReply!.data()['username'],
                            'ccs_driver',
                          ),
                          text: stringFromFirebase(
                            replyingToForumReply!.data()['text'],
                            '',
                          ),
                          photoUrl: stringFromFirebase(
                            replyingToForumReply!.data()['photoUrl'],
                            stringFromFirebase(
                              replyingToForumReply!.data()['imageUrl'],
                              '',
                            ),
                          ),
                        ),
                        compact: true,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => replyingToForumReply = null),
                          icon: const Icon(Icons.close, size: 16),
                          label: CcsText(trText('Cancel reply')),
                        ),
                      ),
                    ],
                    if (pendingPhotoAttachmentPath != null)
                      stagedChatPhotoPreview(
                        localPhotoPath: pendingPhotoAttachmentPath!,
                        isBusy: isSending || isUploadingPhotoAttachment,
                        onRemove: () {
                          setState(() => pendingPhotoAttachmentPath = null);
                        },
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: trText('Take photo'),
                          onPressed:
                              isUploadingPhotoAttachment ||
                                  pendingPhotoAttachmentPath != null
                              ? null
                              : () => controller.attachPhoto(useCamera: true),
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            color: blue,
                          ),
                        ),
                        IconButton(
                          tooltip: trText('Photo'),
                          onPressed: isUploadingPhotoAttachment
                              ? null
                              : controller.attachPhoto,
                          constraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(foregroundColor: blue),
                          icon: Icon(
                            isUploadingPhotoAttachment
                                ? Icons.hourglass_top
                                : Icons.photo_library_outlined,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: MentionTextField(
                            controller: replyController,
                            focusNode: replyFocusNode,
                            minLines: 1,
                            maxLines: 3,
                            keyboardType: TextInputType.multiline,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: trText('Reply in topic'),
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF1A1A1A),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2A2A2A),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2A2A2A),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: blue),
                              ),
                            ),
                            onSubmitted: (_) => controller.sendReply(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: isSending ? null : controller.sendReply,
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
                          icon: Icon(
                            isSending ? Icons.hourglass_top : Icons.send,
                          ),
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
