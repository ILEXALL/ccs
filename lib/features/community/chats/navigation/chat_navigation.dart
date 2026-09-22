import 'package:flutter/widgets.dart';
import 'package:ccs_app/features/friends/models/friend_user.dart';

// Bound by app composition before any screen is mounted.
typedef DirectChatNavigation =
    Future<void> Function(BuildContext context, FriendUserData user);
late DirectChatNavigation directChatNavigation;
Future<void> openMessageToUserFromContext(
  BuildContext context,
  FriendUserData user,
) => directChatNavigation(context, user);
