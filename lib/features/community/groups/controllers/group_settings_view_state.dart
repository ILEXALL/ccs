import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

abstract interface class GroupSettingsInputs {
  ChatThreadData get chat;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class GroupSettingsViewState {
  BuildContext get context;
  bool get mounted;
  GroupSettingsInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get nameController;
  TextEditingController get descriptionController;
  List<String> get memberIds;
  set memberIds(List<String> value);
  List<String> get memberUsernames;
  set memberUsernames(List<String> value);
  List<String> get memberPhotoUrls;
  set memberPhotoUrls(List<String> value);
  List<String> get moderatorIds;
  set moderatorIds(List<String> value);
  String get ownerUid;
  set ownerUid(String value);
  bool get isPrivate;
  set isPrivate(bool value);
  bool get isSaving;
  set isSaving(bool value);
  String get photoUrl;
  set photoUrl(String value);
  GroupSettingsContentActions get content;
  GroupSettingsControllerActions get controller;
}

abstract interface class GroupSettingsContentActions {
  Widget avatarPreview();
  Widget memberTile(FriendUserData user);
  Widget membersSection();
}

abstract interface class GroupSettingsControllerActions {
  Future<void> pickGroupAvatar();
  bool get isCurrentUserGroupOwner;
  bool get currentUserCanOverridePrivateGroup;
  bool get canManageGroupMembers;
  bool get canEditGroupDetails;
  ChatThreadData get localChatData;
  Future<void> addMembersToGroup();
  Future<void> toggleGroupModerator(FriendUserData user);
  bool canRemoveGroupMember(FriendUserData user);
  Future<void> permanentlyDenyGroupMember(FriendUserData user);
  Future<void> removeGroupMember(FriendUserData user);
  Future<void> saveGroup();
  Future<void> removeGroupOrLeave();
  Future<void> deleteGroupExplicitly();
}
