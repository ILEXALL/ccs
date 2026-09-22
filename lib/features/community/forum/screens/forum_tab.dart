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
    show forumTopicIsVisibleNow, loadRegionalForumTopicDocuments;
import 'package:ccs_app/features/community/forum/data/forum_state.dart'
    show forumTopicsRefreshTick;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show
        ForumCategoryConfig,
        forumCategoryById,
        forumCategoryConfigs,
        forumCategoryDescription,
        forumCategoryIdFromFirebase,
        forumCategoryTitle;
import 'package:ccs_app/features/community/forum/screens/forum_category_page.dart'
    show ForumCategoryPage, ForumTopicFallbackAvatar;
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

class ForumTab extends StatefulWidget {
  const ForumTab({super.key});

  @override
  State<ForumTab> createState() => _ForumTabState();
}

class _ForumTabState extends State<ForumTab>
    with AutomaticKeepAliveClientMixin, LanguageReactiveState {
  final scrollController = ScrollController();
  final searchController = TextEditingController();
  final topics = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool isLoading = false;
  bool hasMore = true;
  bool didLoadInitially = false;
  int handledRefreshTick = 0;
  Timer? expiredTopicRefreshTimer;
  String searchQuery = '';
  bool pendingCountryReload = false;

  @override
  bool get wantKeepAlive => true;

  CollectionReference<Map<String, dynamic>> get forumTopicsCollection =>
      FirebaseFirestore.instance.collection('forum_topics');

  @override
  void initState() {
    super.initState();
    handledRefreshTick = forumTopicsRefreshTick.value;
    scrollController.addListener(handleScroll);
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
    unawaited(refreshTopics());
  }

  void handleExternalForumRefresh() {
    if (!mounted || handledRefreshTick == forumTopicsRefreshTick.value) {
      return;
    }

    handledRefreshTick = forumTopicsRefreshTick.value;
    unawaited(refreshTopics());
  }

  void handleCommunityCountryChanged() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (isLoading) {
      pendingCountryReload = true;
      setState(() => topics.clear());
      return;
    }
    unawaited(refreshTopics());
  }

  @override
  void dispose() {
    scrollController.removeListener(handleScroll);
    forumTopicsRefreshTick.removeListener(handleExternalForumRefresh);
    communityCountrySelection.removeListener(handleCommunityCountryChanged);
    expiredTopicRefreshTimer?.cancel();
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void handleScroll() {
    if (!scrollController.hasClients || isLoading || !hasMore) {
      return;
    }

    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      unawaited(loadMoreTopics());
    }
  }

  Future<void> refreshTopics() async {
    setState(() {
      topics.clear();
      hasMore = true;
      didLoadInitially = false;
    });
    await loadMoreTopics();
  }

  Future<void> loadMoreTopics() async {
    if (isLoading) {
      return;
    }

    setState(() => isLoading = true);

    try {
      final regionalDocs = await loadRegionalForumTopicDocuments(
        forumTopicsCollection,
        'forum: topics dashboard get',
      );

      final docs =
          regionalDocs.where((doc) {
            return forumTopicIsVisibleNow(doc.data()) &&
                (doc.data()['visibility'] == 'group' ||
                    communityContentCountryCode(doc.data()) ==
                        communityCountrySelection.value);
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

      if (!mounted || pendingCountryReload) return;
      setState(() {
        topics
          ..clear()
          ..addAll(docs);
        hasMore = false;
        didLoadInitially = true;
      });
    } catch (error, stack) {
      debugPrint('Forum topics load skipped: $error');
      debugPrint('$stack');
      if (mounted) {
        setState(() {
          didLoadInitially = true;
          hasMore = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        if (pendingCountryReload) {
          pendingCountryReload = false;
          unawaited(refreshTopics());
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
      final categoryId = forumCategoryIdFromFirebase(
        data['categoryId'] ?? data['category'],
      );
      final category = forumCategoryTitle(categoryId).toLowerCase();
      return title.contains(query) ||
          description.contains(query) ||
          author.contains(query) ||
          category.contains(query);
    }).toList();
  }

  Future<void> openTopicCreator(String categoryId) async {
    await Navigator.push(
      context,
      appPageRoute(
        builder: (_) => NewForumTopicPage(initialCategory: categoryId),
      ),
    );
  }

  Future<void> openForumCategory(String categoryId) async {
    await Navigator.push(
      context,
      appPageRoute(builder: (_) => ForumCategoryPage(categoryId: categoryId)),
    );
  }

  Widget forumSearchBar() {
    return TextField(
      controller: searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: trText('Search topics, categories, keywords...'),
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

  Widget categoryCard(
    ForumCategoryConfig category,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredTopics,
  ) {
    final categoryTopics = filteredTopics.where((doc) {
      final data = doc.data();
      return forumCategoryIdFromFirebase(
            data['categoryId'] ?? data['category'],
          ) ==
          category.id;
    }).toList();

    return InkWell(
      onTap: () => openForumCategory(category.id),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101722),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF253246)),
          boxShadow: [
            BoxShadow(
              color: blue.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
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
                    forumCategoryTitle(category.id),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CcsText(
                    forumCategoryDescription(category.id),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ForumUnreadBadge(categoryId: category.id),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CcsText(
                  '${categoryTopics.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                CcsText(
                  trText('topics'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: blue),
          ],
        ),
      ),
    );
  }

  Widget topicCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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
    final categoryId = forumCategoryIdFromFirebase(
      data['categoryId'] ?? data['category'],
    );
    final category = forumCategoryById(categoryId);
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
                          icon: category.icon,
                          size: 64,
                        ),
                      )
                    : ForumTopicFallbackAvatar(icon: category.icon, size: 64),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
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
                            fallbackGlobalChatModerator:
                                fallbackGlobalModerator,
                            compact: true,
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: blue.withValues(alpha: 0.35),
                          ),
                        ),
                        child: CcsText(
                          forumCategoryTitle(categoryId),
                          style: const TextStyle(
                            color: blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
    super.build(context);

    if (!didLoadInitially && isLoading) {
      return const Center(child: CircularProgressIndicator(color: blue));
    }

    final filteredTopics = visibleTopics();

    return RefreshIndicator(
      onRefresh: refreshTopics,
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 92),
        children: [
          CcsText(
            trText('Forum'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          CcsText(
            trText('Find topics by category'),
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: CommunityCountrySelector(),
          ),
          const SizedBox(height: 18),
          forumSearchBar(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: CcsText(
                  trText('Categories'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              CcsText(
                trText('Tap a category'),
                style: const TextStyle(
                  color: blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final category in forumCategoryConfigs)
            categoryCard(category, filteredTopics),
          const SizedBox(height: 8),
          if (filteredTopics.isEmpty)
            EmptyStateCard(
              icon: Icons.forum_outlined,
              title: trText('No forum topics yet'),
              text: trText('Open a category to create the first topic.'),
            ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator(color: blue)),
            ),
        ],
      ),
    );
  }
}
