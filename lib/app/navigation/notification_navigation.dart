import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show isValidLatLngValues;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show communityCountrySelection, currentUser;
import 'package:ccs_app/features/community/chats/screens/chat_conversation_screen.dart'
    show ChatConversationScreen;
import 'package:ccs_app/features/community/forum/screens/forum_topic_page.dart'
    show ForumTopicPage;
import 'package:ccs_app/features/community/groups/screens/group_join_requests.dart'
    show GroupJoinRequestsScreen;
import 'package:ccs_app/features/community/screens/community_screen.dart'
    show ChatScreen;
import 'package:ccs_app/features/friends/screens/friends_screen.dart'
    show FriendsScreen;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show MapFocusRequest, mapFocusRequest;
import 'package:ccs_app/features/moderation/screens/admin_review_screen.dart'
    show AdminReviewScreen;
import 'package:ccs_app/features/moderation/screens/admin_users_screen.dart'
    show AdminUsersScreen;
import 'package:ccs_app/features/moderation/screens/spot_review_screen.dart'
    show AdminSpotReviewScreen;
import 'package:ccs_app/features/moderation/screens/user_reports_screen.dart'
    show AdminUserReportsScreen;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show inAppBadges;
import 'package:ccs_app/features/notifications/data/notification_repository.dart'
    show markNotificationReadBestEffort;
import 'package:ccs_app/features/notifications/data/notification_targets.dart'
    show chatForNotificationItem, spotForNotificationItem;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;
import 'package:ccs_app/features/progression/data/xp_access.dart'
    show canReadXpStatsForUser;
import 'package:ccs_app/features/progression/screens/xp_history_screen.dart'
    show XpHistoryScreen;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/models/spot_navigation_result.dart'
    show SpotDetailNavigationResult;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;

Future<void> navigateToNotification(
  BuildContext context,
  NotificationCenterItem item,
) async {
  if (item.reference != null) {
    unawaited(markNotificationReadBestEffort(item.reference!));
  }

  if (item.type == 'xp_reward') {
    final currentUid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? currentUser.uid.trim();
    final cleanUserId = item.userId.trim().isNotEmpty
        ? item.userId.trim()
        : currentUid;
    if (cleanUserId.isNotEmpty && canReadXpStatsForUser(cleanUserId)) {
      Navigator.push(
        context,
        appPageRoute(builder: (_) => XpHistoryScreen(userId: cleanUserId)),
      );
    }
    return;
  }

  if (item.type == 'global_chat_message' || item.type == 'global_chat_admin') {
    // Legacy untagged global notifications belong to the original LV channel.
    var country = countryIsoCode(item.countryCode);
    if (country == null && item.messageId.trim().isNotEmpty) {
      try {
        final message = await FirebaseFirestore.instance
            .collection('global_chat')
            .doc(item.messageId.trim())
            .debugGet(
              const GetOptions(source: Source.server),
              'notification: resolve global message country',
            );
        country = countryIsoCode(
          stringFromFirebase(message.data()?['countryCode'], ''),
        );
      } catch (error) {
        debugPrint('Could not resolve notification country: $error');
      }
      if (!context.mounted) return;
    }
    country ??= 'LV';
    communityCountrySelection.value = country;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) unawaited(inAppBadges.start(uid, countryCode: country));
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const ChatScreen(initialTabIndex: 2)),
    );
    return;
  }

  if ((item.type == 'forum_topic_created' ||
          item.type == 'forum_reply' ||
          item.type == 'forum_topic_pending' ||
          item.type == 'forum_reply_admin') &&
      item.topicId.trim().isNotEmpty) {
    Navigator.push(
      context,
      appPageRoute(
        builder: (_) => ForumTopicPage(
          topicId: item.topicId.trim(),
          title: item.title,
          countryCode: item.countryCode,
        ),
      ),
    );
    return;
  }

  if (item.type == 'chat_message') {
    final chat = await chatForNotificationItem(item);
    if (!context.mounted) return;

    if (chat != null) {
      Navigator.push(
        context,
        appPageRoute(builder: (_) => ChatConversationScreen(chat: chat)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            trText('Chat is not available anymore.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return;
  }

  if (item.type == 'moderator_user_banned' &&
      currentUser.role == UserRole.admin) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const AdminUsersScreen()),
    );
    return;
  }

  if (item.type == 'user_report_new' && userRoleIsStaff(currentUser.role)) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const AdminUserReportsScreen()),
    );
    return;
  }

  if (item.type == 'group_join_request') {
    Navigator.push(
      context,
      appPageRoute(
        builder: (_) => GroupJoinRequestsScreen(chatId: item.chatId),
      ),
    );
    return;
  }
  if (item.type == 'group_join_decision' ||
      item.type == 'group_members_added') {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const ChatScreen(initialTabIndex: 1)),
    );
    return;
  }

  if (item.type == 'friend_request') {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const FriendsScreen(initialTabIndex: 1)),
    );
    return;
  }

  // For likes and comments, try to open the spot directly from either the
  // stored spot id or the spot name recovered from older notification bodies.
  if (item.type == 'spot_like' || item.type == 'spot_comment') {
    final likeSpot = await spotForNotificationItem(item);
    if (!context.mounted) return;

    if (likeSpot != null) {
      final navigationResult = await Navigator.push<SpotDetailNavigationResult>(
        context,
        appPageRoute(builder: (_) => SpotDetailScreen(spot: likeSpot)),
      );
      if (!context.mounted) return;
      if (navigationResult == SpotDetailNavigationResult.showMap) {
        Navigator.of(context).maybePop();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            trText('Spot is not available anymore.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return;
  }

  if (item.type == 'friend_nearby' ||
      item.type == 'friend_at_spot' ||
      item.type == 'friend_live_sharing') {
    if ((item.friendLat != 0 || item.friendLng != 0) &&
        isValidLatLngValues(item.friendLat, item.friendLng)) {
      mapFocusRequest.value = MapFocusRequest(
        spotId: item.spotId.trim(),
        coordinates: LatLng(item.friendLat, item.friendLng),
      );
      Navigator.of(context).maybePop();
      return;
    }

    final cleanFriendUid = item.actorUserId.trim().isNotEmpty
        ? item.actorUserId.trim()
        : item.addedByUid.trim().isNotEmpty
        ? item.addedByUid.trim()
        : item.userId.trim();
    if (cleanFriendUid.isNotEmpty) {
      openUserProfile(context, uid: cleanFriendUid);
      return;
    }
  }

  final cleanProfileUid = item.addedByUid.trim().isNotEmpty
      ? item.addedByUid.trim()
      : item.userId.trim();
  if (cleanProfileUid.isNotEmpty &&
      (item.type == 'friend_nearby' || item.type == 'friend_at_spot')) {
    openUserProfile(context, uid: cleanProfileUid);
    return;
  }

  final spot = await spotForNotificationItem(item);
  if (!context.mounted) return;

  if (spot == null) {
    if (item.type == 'spot_pending_review' &&
        userRoleIsStaff(currentUser.role)) {
      Navigator.push(
        context,
        appPageRoute(builder: (_) => const AdminReviewScreen()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          trText('Spot is not available anymore.'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return;
  }

  if (userRoleIsStaff(currentUser.role) &&
      (item.type == 'spot_pending_review' ||
          item.type == 'spot_approved_by_admin' ||
          item.type == 'spot_rejected_by_admin')) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => AdminSpotReviewScreen(spot: spot)),
    );
    return;
  }

  final navigationResult = await Navigator.push<SpotDetailNavigationResult>(
    context,
    appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
  );
  if (!context.mounted) return;
  if (navigationResult == SpotDetailNavigationResult.showMap) {
    Navigator.of(context).maybePop();
  }
}
