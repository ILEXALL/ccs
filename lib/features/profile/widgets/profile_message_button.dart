import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/navigation/chat_navigation.dart'
    show openMessageToUserFromContext;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

Widget profileMessageButton(BuildContext context, FriendUserData user) {
  if (user.uid == currentUser.uid) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
    child: SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => openMessageToUserFromContext(context, user),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const CcsText('Message'),
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
  );
}
