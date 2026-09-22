import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/features/notifications/controllers/in_app_badges.dart';
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/chats/screens/chats_tab.dart'
    show ChatsTab;
import 'package:ccs_app/features/community/chats/screens/new_chat_screen.dart'
    show NewChatScreen;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show SegmentBadgeIcon;
import 'package:ccs_app/features/community/forum/screens/forum_tab.dart'
    show ForumTab;
import 'package:ccs_app/features/community/forum/screens/new_forum_topic.dart'
    show NewForumTopicPage;
import 'package:ccs_app/features/community/global_chat/screens/global_chat_tab.dart'
    show GlobalChatTab;
import 'package:ccs_app/features/community/groups/screens/groups_tab.dart'
    show GroupsTab;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show
        activityChatTabIndex,
        chatActivitySection,
        chatUnreadCountsByChatId,
        globalChatTabSelectedForNotifications,
        inAppBadges,
        mainChatScreenVisibleForNotifications;
import 'package:ccs_app/features/progression/screens/leaderboard_screen.dart'
    show XpLeaderboardScreen;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class ChatScreen extends StatefulWidget {
  final int initialTabIndex;
  final bool isMainTab;

  const ChatScreen({
    super.key,
    this.initialTabIndex = 0,
    this.isMainTab = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> chatsStream;
  int activeTabIndex = 0;
  ActivitySection? _previousBadgeSection;

  @override
  void initState() {
    super.initState();
    appUiPreferences.addListener(_handleLanguageChanged);
    final initialIndex = widget.initialTabIndex.clamp(0, 4).toInt();
    activeTabIndex = initialIndex;
    if (widget.isMainTab) {
      activityChatTabIndex = initialIndex;
    } else {
      _previousBadgeSection = inAppBadges.visibleSection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) inAppBadges.visit(chatActivitySection(initialIndex));
      });
    }
    tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: initialIndex,
    );
    globalChatTabSelectedForNotifications = initialIndex == 2;
    tabController.addListener(handleTabChanged);
    chatsStream = inAppBadges.chats;
  }

  @override
  void dispose() {
    globalChatTabSelectedForNotifications = false;
    if (!widget.isMainTab) {
      inAppBadges.visibleSection = _previousBadgeSection;
    }
    appUiPreferences.removeListener(_handleLanguageChanged);
    tabController.removeListener(handleTabChanged);
    tabController.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void handleTabChanged() {
    globalChatTabSelectedForNotifications = tabController.index == 2;
    if (widget.isMainTab) activityChatTabIndex = tabController.index;
    if (!widget.isMainTab || mainChatScreenVisibleForNotifications) {
      inAppBadges.visit(chatActivitySection(tabController.index));
    }
    if (activeTabIndex != tabController.index) {
      // A composer can retain focus because every tab stays mounted inside the
      // TabBarView. Explicitly release it whenever the user changes chat tabs
      // so the keyboard does not cover the newly selected screen.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => activeTabIndex = tabController.index);
    }
  }

  Future<void> openNewChat(
    BuildContext context, {
    bool groupMode = false,
  }) async {
    await Navigator.push(
      context,
      appPageRoute(builder: (_) => NewChatScreen(initialGroupMode: groupMode)),
    );
  }

  Future<void> openNewForumTopic(BuildContext context) async {
    await Navigator.push(
      context,
      appPageRoute(builder: (_) => const NewForumTopicPage()),
    );
  }

  List<ChatThreadData> sortedChats(List<ChatThreadData> chats) {
    chats.sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));
    return chats;
  }

  FloatingActionButton? contextualFab() {
    if (activeTabIndex >= 2) {
      return null;
    }

    if (activeTabIndex == 3) {
      return null;
    }

    return FloatingActionButton(
      onPressed: () => openNewChat(context, groupMode: activeTabIndex == 1),
      backgroundColor: blue,
      foregroundColor: Colors.white,
      child: Icon(activeTabIndex == 1 ? Icons.group_add : Icons.add),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const CcsAppBarLogo(),
          backgroundColor: Colors.transparent,
          foregroundColor: blue,
          actions: ccsAppBarActions(),
        ),
        body: const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: EmptyStateCard(
            icon: Icons.chat_bubble_outline,
            title: 'Log in required',
            text: 'Log in before using chat.',
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: chatsStream,
      builder: (context, snapshot) {
        final chats =
            snapshot.data?.docs
                .map((doc) => ChatThreadData.fromFirestore(doc))
                .where((chat) => !chat.isHiddenFor(firebaseUser.uid))
                .toList() ??
            <ChatThreadData>[];
        final directChats = sortedChats(
          chats.where((chat) => !chat.isGroup).toList(),
        );
        final groupChats = sortedChats(
          chats.where((chat) => chat.isGroup).toList(),
        );

        return AnimatedBuilder(
          animation: inAppBadges,
          builder: (context, _) => ValueListenableBuilder<Map<String, int>>(
            valueListenable: chatUnreadCountsByChatId,
            builder: (context, unreadCountsByChatId, _) {
              final directUnreadCount = inAppBadges.count(
                ActivitySection.direct,
              );
              final groupUnreadCount = inAppBadges.count(
                ActivitySection.groups,
              );

              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: const CcsAppBarLogo(),
                  backgroundColor: Colors.transparent,
                  foregroundColor: blue,
                  actions: ccsAppBarActions(),
                ),
                floatingActionButton: contextualFab(),
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: appUiPreferences,
                          builder: (context, _) {
                            return TabBar(
                              controller: tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.center,
                              padding: EdgeInsets.zero,
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              indicatorColor: blue,
                              indicatorWeight: 2,
                              labelColor: blue,
                              unselectedLabelColor: Colors.white54,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                              tabs: [
                                Tab(
                                  iconMargin: const EdgeInsets.only(bottom: 1),
                                  icon: SegmentBadgeIcon(
                                    icon: Icons.chat_bubble_outline,
                                    count: directUnreadCount,
                                  ),
                                  text: trText('Chats'),
                                ),
                                Tab(
                                  iconMargin: const EdgeInsets.only(bottom: 1),
                                  icon: SegmentBadgeIcon(
                                    icon: Icons.groups,
                                    count: groupUnreadCount,
                                  ),
                                  text: trText('Groups'),
                                ),
                                Tab(
                                  iconMargin: const EdgeInsets.only(bottom: 1),
                                  icon: SegmentBadgeIcon(
                                    icon: Icons.public,
                                    count: inAppBadges.count(
                                      ActivitySection.global,
                                    ),
                                  ),
                                  text: trText('Global'),
                                ),
                                Tab(
                                  iconMargin: const EdgeInsets.only(bottom: 1),
                                  icon: SegmentBadgeIcon(
                                    icon: Icons.forum_outlined,
                                    count: inAppBadges.count(
                                      ActivitySection.forum,
                                    ),
                                  ),
                                  text: trText('Forum'),
                                ),
                                Tab(
                                  icon: const Icon(Icons.emoji_events_outlined),
                                  text: achievementText(
                                    appUiPreferences.language.name,
                                    'Ranking',
                                    'Рейтинг',
                                    'Reitings',
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: tabController,
                        children: [
                          ChatsTab(
                            chats: directChats,
                            currentUid: firebaseUser.uid,
                            unreadCountsByChatId: unreadCountsByChatId,
                          ),
                          GroupsTab(
                            chats: groupChats,
                            currentUid: firebaseUser.uid,
                            unreadCountsByChatId: unreadCountsByChatId,
                          ),
                          GlobalChatTab(isActive: activeTabIndex == 2),
                          const ForumTab(),
                          const XpLeaderboardScreen(embedded: true),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
