import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/location/startup_location.dart';
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/features/notifications/controllers/in_app_badges.dart';
import 'package:ccs_app/app/gates/profile_region_gate.dart'
    show ProfileRegionGate;
import 'package:ccs_app/core/config/app_config.dart'
    show friendLocationNotificationPollingEnabled;
import 'package:ccs_app/core/firestore/collections.dart'
    show
        adminNotificationsCollection,
        meetNotificationsCollection,
        userNotificationsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show doubleFromFirebase, stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugQueryExtension,
        firestoreDebugTracker;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show setAppIconBadgeCount;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show accountSigningOut, communityCountrySelection, currentUser;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show startCurrentUserDocumentWatcher;
import 'package:ccs_app/features/community/screens/community_screen.dart'
    show ChatScreen;
import 'package:ccs_app/features/friends/data/friend_requests.dart'
    show incomingFriendRequestCountStream;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show mapFocusRequest;
import 'package:ccs_app/features/map/data/live_presence.dart'
    show updateCurrentUserOnlinePresence;
import 'package:ccs_app/features/map/screens/map_screen.dart' show MapScreen;
import 'package:ccs_app/features/moderation/data/debug_preferences.dart'
    show firestoreDebugButtonVisible, loadFirestoreDebugButtonPreference;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserRegionIsRestricted, moderationNotificationAllowed;
import 'package:ccs_app/features/moderation/screens/firestore_debug_screen.dart'
    show FirestoreDebugScreen;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show
        activityChatTabIndex,
        activitySectionForNavigation,
        appIsForegroundForNotifications,
        chatUnreadCountsByChatId,
        inAppBadges,
        mainChatScreenVisibleForNotifications,
        notificationCenterUnreadCount;
import 'package:ccs_app/features/notifications/data/badge_sync.dart'
    show observeLoadedSpotsForBadges;
import 'package:ccs_app/features/notifications/data/friend_location_notifications.dart'
    show checkFriendLocationNotifications;
import 'package:ccs_app/features/notifications/data/push_notifications.dart'
    show initializePushNotificationsForCurrentUser;
import 'package:ccs_app/features/notifications/models/badge_label.dart'
    show compactBadgeLabel;
import 'package:ccs_app/features/notifications/data/unread_notifications.dart'
    show
        scheduleNotificationCenterUnreadRefresh,
        startNotificationCenterUnreadWatcher;
import 'package:ccs_app/features/progression/widgets/level_up_feedback_host.dart';
import 'package:ccs_app/features/profile/screens/profile_screen.dart'
    show ProfileScreen;
import 'package:ccs_app/features/spots/data/spot_feed_state.dart'
    show currentSpotSyncScope, spotSyncScope, spotSyncSubscriptions;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show spotSyncRetryTimer, startFirebaseSpotSync;
import 'package:ccs_app/features/spots/models/creation_kind.dart'
    show CreationKind, showCreationMenu;
import 'package:ccs_app/features/spots/screens/add_spot_screen.dart'
    show AddSpotScreen;
import 'package:ccs_app/features/spots/screens/explore_screen.dart'
    show ExploreScreen;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/region_unavailable_dialog.dart'
    show showRegionFeatureUnavailableDialog;

class MainScreen extends StatelessWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: accountSigningOut,
    builder: (context, leaving, _) => leaving
        ? const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          )
        : ProfileRegionGate(
            child: Builder(
              builder: (_) => LevelUpFeedbackHost(
                userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                child: _MainContentScreen(initialIndex: initialIndex),
              ),
            ),
          ),
  );
}

class _MainContentScreen extends StatefulWidget {
  final int initialIndex;

  const _MainContentScreen({this.initialIndex = 0});

  @override
  State<_MainContentScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<_MainContentScreen>
    with WidgetsBindingObserver {
  late int index;
  final List<int> tabHistory = [];
  bool creatingEvent = false;
  bool creatingPrivateEvent = false;
  bool hasOpenedMap = false;
  bool hasOpenedChat = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  meetNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  adminNotificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  friendLocationNotificationSubscription;
  Timer? friendLocationCheckTimer;
  Timer? onlinePresenceRefreshTimer;
  bool isCheckingFriendLocationNotifications = false;

  List<Widget> get screens => [
    ExploreScreen(isVisible: index == 0),
    hasOpenedMap ? MapScreen(isVisible: index == 1) : const SizedBox.shrink(),
    AddSpotScreen(
      key: ValueKey('$creatingEvent/$creatingPrivateEvent'),
      eventMode: creatingEvent,
      privateEvent: creatingPrivateEvent,
    ),
    hasOpenedChat ? const ChatScreen(isMainTab: true) : const SizedBox.shrink(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !accountSigningOut.value &&
          FirebaseAuth.instance.currentUser != null) {
        unawaited(initializeStartupLocation());
      }
    });
    index = widget.initialIndex.clamp(0, 4).toInt();
    hasOpenedMap = index == 1;
    hasOpenedChat = index == 3;
    activityChatTabIndex = 0;
    inAppBadges.visibleSection = activitySectionForNavigation(index);
    inAppBadges.onReady = observeLoadedSpotsForBadges;
    final badgeUid = FirebaseAuth.instance.currentUser?.uid;
    if (badgeUid != null) {
      unawaited(
        inAppBadges.start(
          badgeUid,
          countryCode: communityCountrySelection.value,
        ),
      );
    }
    mainChatScreenVisibleForNotifications = index == 3;
    appIsForegroundForNotifications = true;
    WidgetsBinding.instance.addObserver(this);
    mapFocusRequest.addListener(handleMapFocusRequest);
    if (mapFocusRequest.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          handleMapFocusRequest();
        }
      });
    }
    unawaited(loadFirestoreDebugButtonPreference());
    unawaited(initializePushNotificationsForCurrentUser());
    startNotificationCenterUnreadWatcher();
    updateCurrentUserOnlinePresence(isOnline: true);
    onlinePresenceRefreshTimer = Timer.periodic(const Duration(seconds: 90), (
      _,
    ) {
      if (appIsForegroundForNotifications) {
        updateCurrentUserOnlinePresence(isOnline: true);
      }
    });
    // Keep general notification collections lazy, but admins/community
    // moderators need a live admin_notifications listener so review and
    // moderation events appear immediately while the app is foregrounded.
    // startMeetNotificationListener();
    startAdminNotificationListener();
    // startFriendLocationNotificationListener();
    // startFriendLocationNotificationChecks();
  }

  void handleMapFocusRequest() {
    if (mapFocusRequest.value == null || !mounted) {
      return;
    }

    if (index != 1 || !hasOpenedMap) {
      selectBottomTab(1);
    }
  }

  void selectBottomTab(int nextIndex) {
    final cleanIndex = nextIndex.clamp(0, 4).toInt();
    if (cleanIndex == 2 && currentUserRegionIsRestricted) {
      unawaited(showRegionFeatureUnavailableDialog(context));
      return;
    }
    inAppBadges.visit(activitySectionForNavigation(cleanIndex));
    if (cleanIndex == index) {
      return;
    }

    setState(() {
      if (tabHistory.isEmpty || tabHistory.last != index) {
        tabHistory.add(index);
      }
      if (tabHistory.length > 12) {
        tabHistory.removeAt(0);
      }

      if (cleanIndex == 1) {
        hasOpenedMap = true;
      } else if (cleanIndex == 3) {
        hasOpenedChat = true;
      }
      index = cleanIndex;
      mainChatScreenVisibleForNotifications = index == 3;
    });
  }

  Future<bool> handleSystemBack() async {
    if (ModalRoute.of(context)?.popDisposition ==
        RoutePopDisposition.doNotPop) {
      return false;
    }
    if (tabHistory.isNotEmpty) {
      final previousIndex = tabHistory.removeLast().clamp(0, 4).toInt();
      inAppBadges.visit(activitySectionForNavigation(previousIndex));
      setState(() {
        if (previousIndex == 1) {
          hasOpenedMap = true;
        } else if (previousIndex == 3) {
          hasOpenedChat = true;
        }
        index = previousIndex;
        mainChatScreenVisibleForNotifications = index == 3;
      });
      return false;
    }

    if (index != 0) {
      inAppBadges.visit(ActivitySection.spots);
      setState(() {
        index = 0;
        mainChatScreenVisibleForNotifications = false;
      });
    }
    return false;
  }

  void openMapTab() => selectBottomTab(1);

  void openChatTab() => selectBottomTab(3);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appIsForegroundForNotifications = true;
      final badgeUid = FirebaseAuth.instance.currentUser?.uid;
      if (badgeUid != null) {
        unawaited(
          inAppBadges.start(
            badgeUid,
            countryCode: communityCountrySelection.value,
          ),
        );
      }
      if (FirebaseAuth.instance.currentUser != null) {
        startCurrentUserDocumentWatcher();
        if (spotSyncRetryTimer != null ||
            spotSyncSubscriptions.isEmpty ||
            spotSyncScope != currentSpotSyncScope) {
          startFirebaseSpotSync();
        }
      }
      unawaited(setAppIconBadgeCount(notificationCenterUnreadCount.value));
      updateCurrentUserOnlinePresence(isOnline: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      appIsForegroundForNotifications = false;
      if (state != AppLifecycleState.inactive) {
        inAppBadges.stop(preserveVisibleForumTopic: true);
      }
      unawaited(firestoreDebugTracker.flushPersisted());
      updateCurrentUserOnlinePresence(isOnline: false);
    }
  }

  void startMeetNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    meetNotificationSubscription = meetNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .where('read', isEqualTo: false)
        .limit(20)
        .debugSnapshots('notifications: unread meet notifications listener')
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final spotName = stringFromFirebase(
              data['spotName'],
              'New meet spot',
            );
            final distanceMeters = doubleFromFirebase(
              data['distanceMeters'],
              0,
            );
            final distanceKm = distanceMeters <= 0
                ? ''
                : ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away';

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: blue,
                  content: CcsText(
                    'New meet nearby: $spotName$distanceKm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.debugSet({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startAdminNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null ||
        (!userRoleIsStaff(currentUser.role) &&
            !currentUser.globalChatModerator)) {
      return;
    }

    adminNotificationSubscription = adminNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .where('read', isEqualTo: false)
        .limit(20)
        .debugSnapshots('notifications: unread admin notifications listener')
        .listen(
          (snapshot) async {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) {
                continue;
              }

              final data = change.doc.data() ?? {};
              if (!moderationNotificationAllowed(data)) continue;
              if (data['read'] == true) {
                continue;
              }

              final title = stringFromFirebase(data['title'], 'Admin update');
              final body = stringFromFirebase(data['body'], '').trim();
              final message = body.isEmpty ? title : body;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: panelGlass,
                    content: CcsText(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }

              scheduleNotificationCenterUnreadRefresh();
            }
          },
          onError: (Object error, StackTrace stack) {
            debugPrint('Admin notification listener failed: $error');
            debugPrint('$stack');
          },
        );
  }

  void startFriendLocationNotificationListener() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    friendLocationNotificationSubscription = userNotificationsCollection()
        .where('userId', isEqualTo: firebaseUser.uid)
        .where('read', isEqualTo: false)
        .limit(20)
        .debugSnapshots('notifications: unread friend location listener')
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added &&
                change.type != DocumentChangeType.modified) {
              continue;
            }

            final data = change.doc.data() ?? {};

            if (data['read'] == true) {
              continue;
            }

            final type = stringFromFirebase(data['type'], 'friend_nearby');
            if (type != 'friend_nearby' && type != 'friend_at_spot') {
              continue;
            }
            final friendUsername = stringFromFirebase(
              data['friendUsername'],
              'friend',
            );
            final spotName = stringFromFirebase(data['spotName'], 'a spot');
            final distanceMeters = doubleFromFirebase(
              data['distanceMeters'],
              0,
            );
            final distanceLabel = distanceMeters <= 0
                ? ''
                : distanceMeters >= 1000
                ? ' • ${(distanceMeters / 1000).toStringAsFixed(1)} km away'
                : ' • ${distanceMeters.round()} m away';

            final message = type == 'friend_at_spot'
                ? '@$friendUsername is at $spotName$distanceLabel'
                : '@$friendUsername is nearby$distanceLabel';

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.greenAccent.shade700,
                  content: CcsText(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            await change.doc.reference.debugSet({
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
  }

  void startFriendLocationNotificationChecks() {
    if (!friendLocationNotificationPollingEnabled) {
      friendLocationCheckTimer?.cancel();
      friendLocationCheckTimer = null;
      return;
    }

    runFriendLocationNotificationCheck();
    friendLocationCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => runFriendLocationNotificationCheck(),
    );
  }

  Future<void> runFriendLocationNotificationCheck() async {
    if (isCheckingFriendLocationNotifications) {
      return;
    }

    isCheckingFriendLocationNotifications = true;

    try {
      await checkFriendLocationNotifications();
    } catch (_) {
      // Friend location notifications are best-effort in-app alerts.
    } finally {
      isCheckingFriendLocationNotifications = false;
    }
  }

  @override
  void dispose() {
    mainChatScreenVisibleForNotifications = false;
    inAppBadges.onReady = null;
    inAppBadges.stop();
    appIsForegroundForNotifications = false;
    WidgetsBinding.instance.removeObserver(this);
    mapFocusRequest.removeListener(handleMapFocusRequest);
    onlinePresenceRefreshTimer?.cancel();
    updateCurrentUserOnlinePresence(isOnline: false);
    meetNotificationSubscription?.cancel();
    adminNotificationSubscription?.cancel();
    friendLocationNotificationSubscription?.cancel();
    friendLocationCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appUiPreferences,
      builder: (context, _) {
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

        return WillPopScope(
          onWillPop: handleSystemBack,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: Colors.transparent,
            extendBody: false,
            body: Stack(
              children: [
                IndexedStack(index: index, children: screens),
                ValueListenableBuilder<bool>(
                  valueListenable: firestoreDebugButtonVisible,
                  builder: (context, visible, _) {
                    if (!visible || currentUser.role != UserRole.admin) {
                      return const SizedBox.shrink();
                    }

                    return Positioned(
                      left: 12,
                      top: MediaQuery.of(context).padding.top + 8,
                      child: Material(
                        color: blue.withValues(alpha: 0.88),
                        shape: const CircleBorder(),
                        elevation: 10,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.push(
                              context,
                              appPageRoute(
                                builder: (_) => const FirestoreDebugScreen(),
                              ),
                            );
                          },
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(
                              Icons.bug_report_outlined,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            bottomNavigationBar: keyboardOpen
                ? null
                : SafeArea(
                    top: false,
                    child: Container(
                      height: 62,
                      decoration: BoxDecoration(
                        color: panelGlass,
                        border: const Border(
                          top: BorderSide(color: Colors.white12),
                        ),
                      ),
                      child: AnimatedBuilder(
                        animation: inAppBadges,
                        builder: (context, _) => Row(
                          children: [
                            Expanded(
                              child: _CcsBottomNavItem(
                                icon: Icons.location_on,
                                badgeCount: inAppBadges.count(
                                  ActivitySection.spots,
                                ),
                                label: trText('Spots'),
                                selected: index == 0,
                                onTap: () => selectBottomTab(0),
                              ),
                            ),
                            Expanded(
                              child: _CcsBottomNavItem(
                                icon: Icons.map,
                                badgeCount: inAppBadges.count(
                                  ActivitySection.map,
                                ),
                                label: trText('Map'),
                                selected: index == 1,
                                onTap: openMapTab,
                              ),
                            ),
                            Expanded(
                              child: _CcsBottomNavItem(
                                icon: Icons.add_rounded,
                                label: '',
                                iconSize: 36,
                                prominentAction: true,
                                selected: index == 2,
                                onTap: () async {
                                  final event = await showCreationMenu(context);
                                  if (!mounted || event == null) return;
                                  setState(() {
                                    creatingEvent = event != CreationKind.spot;
                                    creatingPrivateEvent =
                                        event == CreationKind.privateEvent;
                                  });
                                  selectBottomTab(2);
                                },
                              ),
                            ),
                            Expanded(
                              child: ValueListenableBuilder<Map<String, int>>(
                                valueListenable: chatUnreadCountsByChatId,
                                builder: (context, unreadCountsByChatId, _) {
                                  return _CcsBottomNavItem(
                                    icon: Icons.diversity_3_outlined,
                                    label: achievementText(
                                      appUiPreferences.language.name,
                                      'Community',
                                      'Сообщество',
                                      'Kopiena',
                                    ),
                                    selected: index == 3,
                                    badgeCount: inAppBadges.chatCount,
                                    onTap: openChatTab,
                                  );
                                },
                              ),
                            ),
                            Expanded(
                              child: StreamBuilder<int>(
                                stream: incomingFriendRequestCountStream(),
                                initialData: 0,
                                builder: (context, snapshot) {
                                  return _CcsBottomNavItem(
                                    icon: Icons.person_outline,
                                    label: trText('Profile'),
                                    selected: index == 4,
                                    badgeCount: snapshot.data ?? 0,
                                    onTap: () => selectBottomTab(4),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _CcsBottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  final double iconSize;
  final bool prominentAction;

  const _CcsBottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
    this.iconSize = 22,
    this.prominentAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? blue : Colors.white54;
    final iconWidget = prominentAction
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [
                        blue.withValues(alpha: 0.34),
                        blue.withValues(alpha: 0.12),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.06),
                      ],
              ),
              border: Border.all(
                color: selected ? blue.withValues(alpha: 0.85) : Colors.white24,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? blue.withValues(alpha: 0.24)
                      : Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: iconSize * 0.72),
          )
        : Icon(icon, color: color, size: iconSize);

    // Keep every bottom-tab icon on the same Y level.
    return InkWell(
      onTap: onTap,
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 7,
              child: Badge(
                isLabelVisible: badgeCount > 0,
                backgroundColor: Colors.redAccent,
                label: CcsText(compactBadgeLabel(badgeCount)),
                child: iconWidget,
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                top: 33,
                left: 0,
                right: 0,
                child: CcsText(
                  label.replaceAll('\n', ' '),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
