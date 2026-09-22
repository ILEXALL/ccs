import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/data/direct_chats.dart'
    show hideChatForCurrentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/groups/data/group_repository.dart'
    show deleteGroupChat, leaveGroupChat;

bool currentUserOwnsGroupChat(ChatThreadData chat) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  return chat.isGroup && chat.isOwner(uid);
}

bool currentUserCanLeaveGroupChat(ChatThreadData chat) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? currentUser.uid;
  return chat.isGroup &&
      chat.memberIds.contains(uid) &&
      chat.memberIds.length > 1;
}

bool currentUserCanDeleteGroupChat(ChatThreadData chat) {
  // The default removal action leaves a populated group, even for its owner.
  // A separate explicit delete button remains available in group settings.
  return currentUserOwnsGroupChat(chat) && !currentUserCanLeaveGroupChat(chat);
}

String chatRemovalTitle(ChatThreadData chat, {bool forceDeleteGroup = false}) {
  if (!chat.isGroup) {
    return 'Delete chat?';
  }

  return forceDeleteGroup || currentUserCanDeleteGroupChat(chat)
      ? 'Delete group?'
      : 'Leave group?';
}

String chatRemovalBody(ChatThreadData chat, {bool forceDeleteGroup = false}) {
  if (!chat.isGroup) {
    return 'This chat will be removed from your list. New messages will bring it back.';
  }

  return forceDeleteGroup || currentUserCanDeleteGroupChat(chat)
      ? 'This group will be deleted for all members.'
      : currentUserOwnsGroupChat(chat)
      ? 'You will leave this group. Ownership will transfer to another member.'
      : 'You will leave this group and stop receiving messages.';
}

String chatRemovalButtonLabel(
  ChatThreadData chat, {
  bool forceDeleteGroup = false,
}) {
  if (!chat.isGroup) {
    return 'Delete chat';
  }

  return forceDeleteGroup || currentUserCanDeleteGroupChat(chat)
      ? 'Delete group'
      : 'Leave group';
}

String chatRemovalSuccessLabel(
  ChatThreadData chat, {
  bool forceDeleteGroup = false,
}) {
  if (!chat.isGroup) {
    return 'Chat deleted.';
  }

  return forceDeleteGroup || currentUserCanDeleteGroupChat(chat)
      ? 'Group deleted.'
      : 'You left the group.';
}

String chatRemovalErrorLabel(
  ChatThreadData chat, {
  bool forceDeleteGroup = false,
}) {
  if (!chat.isGroup) {
    return 'Could not delete chat.';
  }

  return forceDeleteGroup || currentUserCanDeleteGroupChat(chat)
      ? 'Could not delete group.'
      : 'Could not leave group.';
}

Future<bool> confirmAndRemoveChat(
  BuildContext context,
  ChatThreadData chat, {
  bool forceDeleteGroup = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: panelGlass,
        title: CcsText(
          chatRemovalTitle(chat, forceDeleteGroup: forceDeleteGroup),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: CcsText(
          chatRemovalBody(chat, forceDeleteGroup: forceDeleteGroup),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const CcsText('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: CcsText(
              chatRemovalButtonLabel(chat, forceDeleteGroup: forceDeleteGroup),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return false;
  }

  final successLabel = chatRemovalSuccessLabel(
    chat,
    forceDeleteGroup: forceDeleteGroup,
  );
  final errorLabel = chatRemovalErrorLabel(
    chat,
    forceDeleteGroup: forceDeleteGroup,
  );

  try {
    if (!chat.isGroup) {
      await hideChatForCurrentUser(chat);
    } else if (forceDeleteGroup || currentUserCanDeleteGroupChat(chat)) {
      await deleteGroupChat(chat);
    } else {
      await leaveGroupChat(chat);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            successLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            '$errorLabel $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return false;
  }
}
