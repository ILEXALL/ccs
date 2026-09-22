import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show intFromFirebase, stringFromFirebase, timestampMillisFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityAuthorCountryCode, communityContentCountryCode;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show
        forumTopicIsVisibleNow,
        loadRegionalForumTopicDocuments,
        syncActiveTemporarySpotForumTopics;
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show
        ForumCategoryConfig,
        forumCategoryById,
        forumCategoryDescription,
        forumCategoryIdFromFirebase,
        forumCategoryTitle;
import 'package:ccs_app/features/community/forum/screens/forum_topic_page.dart'
    show ForumTopicPage;
import 'package:ccs_app/features/community/forum/screens/new_forum_topic.dart'
    show NewForumTopicPage;
import 'package:ccs_app/features/community/forum/widgets/forum_badges.dart'
    show ForumUnreadBadge, forumReplyCountBadge;
import 'package:ccs_app/features/community/widgets/country_selector.dart'
    show CommunityAvatarWithCountryFlag, CommunityCountrySelector;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show userDataHasCommunityModerationAccess;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;
import 'package:ccs_app/shared/models/user_role.dart'
    show roleFromFirebase, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_badge.dart'
    show UserPrimaryBadgeForUid;

class ForumCategoryPage extends StatefulWidget {
  final String categoryId;

  const ForumCategoryPage({super.key, required this.categoryId});

  @override
  State<ForumCategoryPage> createState() => _ForumCategoryPageState();
}

class _ForumCategoryPageState extends State<ForumCategoryPage>
    with LanguageReactiveState {
  final searchController = TextEditingController();
  final topics = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool isLoading = false;
  bool didLoadInitially = false;
  String searchQuery = '';
  int handledRefreshTick = 0;
  Timer? expiredTopicRefreshTimer;
  bool pendingCountryReload = false;

  ForumCategoryConfig get category => forumCategoryById(widget.categoryId);

  CollectionReference<Map<String, dynamic>> get forumTopicsCollection =>
      FirebaseFirestore.instance.collection('forum_topics');

  @override
  void initState() {
    super.initState();
    handledRefreshTick = forumTopicsRefreshTick.value;
    forumTopicsRefreshTick.addListener(handleExternalForumRefresh);
    communityCountrySelection.addListener(handleCommunityCountryChanged);
    searchController.addListener(() {
      if (mounted) {
        setState(() => searchQuery = searchController.text.trim());
      }
    });
    expiredTopicRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    if (widget.categoryId == 'meets_events') {
      unawaited(_syncTemporarySpotsThenLoadTopics());
    } else {
      unawaited(loadTopics());
    }
  }

  Future<void> _syncTemporarySpotsThenLoadTopics() async {
    await syncActiveTemporarySpotForumTopics();
    if (!mounted) {
      return;
    }
    await loadTopics();
  }

  void handleExternalForumRefresh() {
    if (!mounted || handledRefreshTick == forumTopicsRefreshTick.value) {
      return;
    }
    handledRefreshTick = forumTopicsRefreshTick.value;
    unawaited(loadTopics());
  }

  void handleCommunityCountryChanged() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (isLoading) {
      pendingCountryReload = true;
      setState(() => topics.clear());
      return;
    }
    unawaited(loadTopics());
  }

  @override
  void dispose() {
    forumTopicsRefreshTick.removeListener(handleExternalForumRefresh);
    communityCountrySelection.removeListener(handleCommunityCountryChanged);
    expiredTopicRefreshTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadTopics() async {
    if (isLoading) {
      return;
    }

    setState(() => isLoading = true);
    try {
      final regionalDocs = await loadRegionalForumTopicDocuments(
        forumTopicsCollection,
        'forum: category topics get',
      );

      final docs =
          regionalDocs.where((doc) {
            final data = doc.data();
            return forumTopicIsVisibleNow(data) &&
                (data['visibility'] == 'group' ||
                    communityContentCountryCode(data) ==
                        communityCountrySelection.value) &&
                forumCategoryIdFromFirebase(
                      data['categoryId'] ?? data['category'],
                    ) ==
                    widget.categoryId;
          }).toList()..sort((a, b) {
            final aPinned = a.data()['isPinned'] == true;
            final bPinned = b.data()['isPinned'] == true;
            if (aPinned != bPinned) {
              return aPinned ? -1 : 1;
            }
            final aMillis = timestampMillisFromFirebase(
              a.data()['lastReplyAt'],
            );
            final bMillis = timestampMillisFromFirebase(
              b.data()['lastReplyAt'],
            );
            return bMillis.compareTo(aMillis);
          });

      if (mounted && !pendingCountryReload) {
        setState(() {
          topics
            ..clear()
            ..addAll(docs);
          didLoadInitially = true;
        });
      }
    } catch (error, stack) {
      debugPrint('Forum category load skipped: $error');
      debugPrint('$stack');
      if (mounted) {
        setState(() => didLoadInitially = true);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        if (pendingCountryReload) {
          pendingCountryReload = false;
          unawaited(loadTopics());
        }
      }
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleTopics() {
    final query = searchQuery.toLowerCase();
    final currentVisibleTopics = topics
        .where((doc) => forumTopicIsVisibleNow(doc.data()))
        .toList();
    if (query.isEmpty) {
      return currentVisibleTopics;
    }

    return currentVisibleTopics.where((doc) {
      final data = doc.data();
      final title = stringFromFirebase(data['title'], '').toLowerCase();
      final description = stringFromFirebase(
        data['description'],
        '',
      ).toLowerCase();
      final author = stringFromFirebase(data['authorName'], '').toLowerCase();
      return title.contains(query) ||
          description.contains(query) ||
          author.contains(query);
    }).toList();
  }

  Future<void> openTopicCreator() async {
    await Navigator.push(
      context,
      appPageRoute(
        builder: (_) => NewForumTopicPage(initialCategory: widget.categoryId),
      ),
    );
  }

  Widget searchBar() {
    return TextField(
      controller: searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: trText('Search topics...'),
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF101722),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF253246)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF253246)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue),
        ),
      ),
    );
  }

  Widget topicCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = stringFromFirebase(data['title'], trText('Untitled topic'));
    final description = stringFromFirebase(data['description'], '');
    final authorId = stringFromFirebase(data['authorId'], '');
    final authorName = stringFromFirebase(data['authorName'], 'ccs_driver');
    final avatarUrl = stringFromFirebase(data['avatarUrl'], '');
    final fallbackRole = roleFromFirebase(data['authorRole'] ?? data['role']);
    final fallbackGlobalModerator =
        data['authorGlobalChatModerator'] == true ||
        data['authorGlobalModerator'] == true ||
        userDataHasCommunityModerationAccess(data);
    final fallbackVerified =
        userRoleIsStaff(fallbackRole) || data['authorVerified'] == true;
    final storedRepliesCount = intFromFirebase(data['repliesCount'], 0);
    final cardCategoryId = forumCategoryIdFromFirebase(
      data['categoryId'] ?? data['category'],
    );
    final cardCategory = forumCategoryById(cardCategoryId);
    final channelCountryCode = communityContentCountryCode(data);
    final authorCountryCode = communityAuthorCountryCode(data);
    final isSpotTopic =
        data['isSpotTopic'] == true ||
        stringFromFirebase(data['source'], '') == 'temporary_spot' ||
        stringFromFirebase(data['temporarySpotId'], '').trim().isNotEmpty;
    final cardAccent = isSpotTopic
        ? Colors.orangeAccent
        : const Color(0xFF253246);
    final cardFill = isSpotTopic
        ? const Color(0xFF0D111A).withValues(alpha: 0.92)
        : const Color(0xFF101722);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(
            builder: (_) => ForumTopicPage(
              topicId: doc.id,
              title: title,
              countryCode: communityContentCountryCode(data),
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSpotTopic
                ? Colors.orangeAccent.withValues(alpha: 0.58)
                : cardAccent,
            width: isSpotTopic ? 1.15 : 1,
          ),
          boxShadow: isSpotTopic
              ? [
                  BoxShadow(
                    color: Colors.orangeAccent.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            CommunityAvatarWithCountryFlag(
              authorCountryCode: authorCountryCode,
              channelCountryCode: channelCountryCode,
              avatar: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: isNetworkUrl(avatarUrl)
                    ? Image.network(
                        avatarUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ForumTopicFallbackAvatar(
                          icon: cardCategory.icon,
                          size: 64,
                        ),
                      )
                    : ForumTopicFallbackAvatar(
                        icon: cardCategory.icon,
                        size: 64,
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
                      Expanded(
                        child: CcsText(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (isSpotTopic) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.orangeAccent.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                          child: CcsText(
                            trText('Spot topic'),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    CcsText(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        height: 1.25,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: CcsText(
                          displayUsername(authorName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ForumUnreadBadge(
              topicId: doc.id,
              countryCode: communityContentCountryCode(data),
            ),
            forumReplyCountBadge(
              topicId: doc.id,
              fallbackCount: storedRepliesCount,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: blue),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleTopics();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: CcsText(forumCategoryTitle(widget.categoryId)),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openTopicCreator,
        backgroundColor: blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: CcsText(
          trText('New topic'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadTopics,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 104),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: CommunityCountrySelector(),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF101722),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF253246)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: blue.withValues(alpha: 0.45)),
                    ),
                    child: Icon(category.icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CcsText(
                          forumCategoryTitle(widget.categoryId),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        CcsText(
                          forumCategoryDescription(widget.categoryId),
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            searchBar(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: CcsText(
                    trText('Topics'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                CcsText(
                  '${visible.length} ${trText('topics')}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!didLoadInitially && isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 42),
                child: Center(child: CircularProgressIndicator(color: blue)),
              )
            else if (visible.isEmpty)
              EmptyStateCard(
                icon: category.icon,
                title: trText('No topics in this category yet'),
                text: trText('Tap New topic to create the first topic.'),
              )
            else
              for (final topic in visible) topicCard(topic),
            if (isLoading && didLoadInitially)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator(color: blue)),
              ),
          ],
        ),
      ),
    );
  }
}

class ForumTopicFallbackAvatar extends StatelessWidget {
  final IconData icon;
  final double size;

  const ForumTopicFallbackAvatar({
    super.key,
    required this.icon,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.14),
        border: Border.all(color: blue.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, color: blue, size: size * 0.45),
    );
  }
}
