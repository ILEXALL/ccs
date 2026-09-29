import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/features/community/global_chat/controllers/global_chat_view_state.dart';
import 'package:ccs_app/features/community/global_chat/widgets/global_chat_content.dart';
import 'package:ccs_app/features/community/global_chat/controllers/global_chat_controller.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show
        nullableTimestampMillisFromFirebase,
        stringFromFirebase,
        timestampMillisFromFirebase;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection, currentUser, currentUserProfileRevision;
import 'package:ccs_app/features/community/chats/widgets/chat_photos.dart'
    show stagedChatPhotoPreview;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/community/widgets/country_selector.dart'
    show CommunityCountrySelector;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show userAppearsOnlineFromPresence;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class GlobalChatTab extends StatefulWidget implements GlobalChatInputs {
  @override
  final bool isActive;

  const GlobalChatTab({super.key, required this.isActive});

  @override
  State<GlobalChatTab> createState() => _GlobalChatTabState();
}

class _GlobalChatTabState extends State<GlobalChatTab>
    with AutomaticKeepAliveClientMixin
    implements GlobalChatViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get stateGlobalMessagesSubscription => _globalMessagesSubscription;

  @override
  set stateGlobalMessagesSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  ) => _globalMessagesSubscription = value;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get stateGlobalMessages =>
      _globalMessages;

  @override
  DocumentSnapshot<Map<String, dynamic>>?
  get stateOldestLoadedGlobalMessageDoc => _oldestLoadedGlobalMessageDoc;

  @override
  set stateOldestLoadedGlobalMessageDoc(
    DocumentSnapshot<Map<String, dynamic>>? value,
  ) => _oldestLoadedGlobalMessageDoc = value;

  @override
  bool get stateIsInitialLoadingGlobalMessages =>
      _isInitialLoadingGlobalMessages;

  @override
  set stateIsInitialLoadingGlobalMessages(bool value) =>
      _isInitialLoadingGlobalMessages = value;

  @override
  bool get stateIsLoadingOlderGlobalMessages => _isLoadingOlderGlobalMessages;

  @override
  set stateIsLoadingOlderGlobalMessages(bool value) =>
      _isLoadingOlderGlobalMessages = value;

  @override
  bool get stateHasMoreOlderGlobalMessages => _hasMoreOlderGlobalMessages;

  @override
  set stateHasMoreOlderGlobalMessages(bool value) =>
      _hasMoreOlderGlobalMessages = value;

  @override
  bool get stateGlobalPaginationInitialized => _globalPaginationInitialized;

  @override
  set stateGlobalPaginationInitialized(bool value) =>
      _globalPaginationInitialized = value;

  @override
  bool get stateScrollGlobalChatToLatestAfterSend =>
      _scrollGlobalChatToLatestAfterSend;

  @override
  set stateScrollGlobalChatToLatestAfterSend(bool value) =>
      _scrollGlobalChatToLatestAfterSend = value;

  @override
  bool get stateGlobalMessagesLoadFailed => _globalMessagesLoadFailed;

  @override
  set stateGlobalMessagesLoadFailed(bool value) =>
      _globalMessagesLoadFailed = value;

  @override
  bool get stateLegacyLatvianMessagesLoaded => _legacyLatvianMessagesLoaded;

  @override
  set stateLegacyLatvianMessagesLoaded(bool value) =>
      _legacyLatvianMessagesLoaded = value;

  @override
  int? get stateLastGlobalChatMessageSentAtMillis =>
      _lastGlobalChatMessageSentAtMillis;

  @override
  set stateLastGlobalChatMessageSentAtMillis(int? value) =>
      _lastGlobalChatMessageSentAtMillis = value;

  @override
  late final GlobalChatContentActions content = GlobalChatContent(this);

  @override
  late final GlobalChatControllerActions controller = GlobalChatController(
    this,
  );

  @override
  final messageController = TextEditingController();
  @override
  final messageFocusNode = FocusNode();
  @override
  final globalChatScrollController = ScrollController();
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>>? onlineUsersStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _globalMessagesSubscription;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _globalMessages = [];
  DocumentSnapshot<Map<String, dynamic>>? _oldestLoadedGlobalMessageDoc;
  bool _isInitialLoadingGlobalMessages = true;
  bool _isLoadingOlderGlobalMessages = false;
  bool _hasMoreOlderGlobalMessages = true;
  bool _globalPaginationInitialized = false;
  bool _scrollGlobalChatToLatestAfterSend = false;
  bool _globalMessagesLoadFailed = false;
  bool _legacyLatvianMessagesLoaded = false;
  @override
  bool isSending = false;
  @override
  bool isUploadingPhotoAttachment = false;
  @override
  String? pendingPhotoAttachmentPath;
  @override
  QueryDocumentSnapshot<Map<String, dynamic>>? replyingToGlobalMessage;
  int? _lastGlobalChatMessageSentAtMillis;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    appUiPreferences.addListener(controller.handleLanguageChanged);
    communityCountrySelection.addListener(
      controller.handleCommunityCountryChanged,
    );
    globalChatScrollController.addListener(controller.onGlobalChatScroll);
    currentUserProfileRevision.addListener(_handleOnlineCounterAccess);
    controller.updateOnlineUsersStream();
    controller.startGlobalMessagesListener();
    unawaited(controller.loadGlobalChatModeratorAccess());
  }

  @override
  void didUpdateWidget(covariant GlobalChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      controller.updateOnlineUsersStream();
    }
  }

  void _handleOnlineCounterAccess() {
    if (!mounted) return;
    controller.updateOnlineUsersStream();
    setState(() {});
  }

  @override
  void dispose() {
    currentUserProfileRevision.removeListener(_handleOnlineCounterAccess);
    appUiPreferences.removeListener(controller.handleLanguageChanged);
    communityCountrySelection.removeListener(
      controller.handleCommunityCountryChanged,
    );
    _globalMessagesSubscription?.cancel();
    globalChatScrollController.removeListener(controller.onGlobalChatScroll);
    globalChatScrollController.dispose();
    messageFocusNode.dispose();
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Column(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: onlineUsersStream,
          builder: (context, snapshot) {
            final count =
                snapshot.data?.docs.where((doc) {
                  final data = doc.data();
                  return (countryIsoCode(
                                stringFromFirebase(data['country'], ''),
                              ) ??
                              'LV') ==
                          controller.selectedCommunityCountryCode &&
                      userAppearsOnlineFromPresence(
                        isOnline: data['isOnline'] == true,
                        lastSeenAtMillis: timestampMillisFromFirebase(
                          data['lastSeenAt'],
                        ),
                        isSharingLiveLocation:
                            data['isSharingLiveLocation'] == true,
                        liveLocationExpiresAtMillis:
                            nullableTimestampMillisFromFirebase(
                              data['liveLocationExpiresAt'],
                            ),
                      );
                }).length ??
                0;
            return Container(
              margin: const EdgeInsets.fromLTRB(0, 0, 0, 1),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: blue.withValues(alpha: 0.42),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, color: blue, size: 20),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: CommunityCountrySelector(compact: true),
                  ),
                  if (currentUser.role == UserRole.admin) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.circle,
                      color: Colors.greenAccent,
                      size: 9,
                    ),
                    const SizedBox(width: 6),
                    CcsText(
                      '$count ${trText('online').toLowerCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Builder(
              builder: (context) {
                final messages =
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                      _globalMessages,
                    );

                if (_isInitialLoadingGlobalMessages) {
                  return const Center(
                    child: CircularProgressIndicator(color: blue),
                  );
                }

                if (_globalMessagesLoadFailed) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: EmptyStateCard(
                      icon: Icons.public_off,
                      title: trText('Global chat unavailable'),
                      text: trText('Could not load global chat right now.'),
                    ),
                  );
                }

                if (messages.isEmpty) {
                  return EmptyStateCard(
                    icon: Icons.public,
                    title: trText('Global chat empty'),
                    text: trText(
                      'Write the first message for the whole community.',
                    ),
                  );
                }

                final messageWidgets = controller.globalChatMessageList(
                  messages,
                );

                return ListView(
                  controller: globalChatScrollController,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  children: [
                    ...messageWidgets.reversed,
                    if (_hasMoreOlderGlobalMessages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: CcsText(
                            trText('Scroll up to load older messages'),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (_isLoadingOlderGlobalMessages)
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
              },
            ),
          ),
        ),
        if (!controller.canPostInSelectedCommunity)
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
                        en: 'Browsing another country is read-only.',
                        ru: 'Просмотр сообщества другой страны доступен только для чтения.',
                        lv: 'Citas valsts kopienu var tikai pārlūkot.',
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
                          controller: messageController,
                          focusNode: messageFocusNode,
                          minLines: 1,
                          maxLines: 3,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: trText('Message in global chat'),
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
                          onSubmitted: (_) => controller.sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: isSending ? null : controller.sendMessage,
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
    );
  }
}
