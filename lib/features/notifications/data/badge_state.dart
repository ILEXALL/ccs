import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/notifications/controllers/in_app_badges.dart';
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show firestoreDebugTracker;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show forumCategoryIdFromFirebase;

final inAppBadges = InAppBadgeController(
  FirebaseFirestore.instance,
  forumCategoryForData: (data) =>
      forumCategoryIdFromFirebase(data['categoryId'] ?? data['category']),
  onRead: (label, readCount) =>
      firestoreDebugTracker.recordRead(label, readCount),
);

int activityChatTabIndex = 0;

ActivitySection? chatActivitySection(int index) =>
    index >= 0 && index < 4 ? ActivitySection.values[index] : null;

ActivitySection? activitySectionForNavigation(int index) => switch (index) {
  0 => ActivitySection.spots,
  1 => ActivitySection.map,
  3 => chatActivitySection(activityChatTabIndex),
  _ => null,
};

final notificationCenterUnreadCount = ValueNotifier<int>(0);

final notificationCenterUnreadCountsBySource = <String, int>{};

final chatUnreadCountsByChatId = ValueNotifier<Map<String, int>>(
  const <String, int>{},
);

// Foreground push suppression needs to know whether the user is actually
// looking at Global Chat. The GlobalChatTab itself is kept alive inside a
// TabBarView, so its mounted state alone is not enough.
bool appIsForegroundForNotifications = true;

bool mainChatScreenVisibleForNotifications = false;

bool globalChatTabSelectedForNotifications = false;

bool get globalChatIsActivelyVisibleForNotifications =>
    appIsForegroundForNotifications &&
    mainChatScreenVisibleForNotifications &&
    globalChatTabSelectedForNotifications;

bool appIconBadgeSyncStarted = false;
