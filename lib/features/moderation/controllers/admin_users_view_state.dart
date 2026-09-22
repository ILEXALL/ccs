import 'package:ccs_app/features/moderation/models/admin_user_sort.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/moderation/models/admin_user.dart'
    show AdminBanInput, AdminUserData;

abstract interface class AdminUsersInputs {
  bool get initialBannedOnly;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class AdminUsersViewState {
  BuildContext get context;
  bool get mounted;
  AdminUsersInputs get widget;
  void updateView(VoidCallback update);
  int get configUsersPerPage;
  bool get bannedOnly;
  set bannedOnly(bool value);
  TextEditingController get searchController;
  FocusNode get searchFocusNode;
  List<DocumentSnapshot<Map<String, dynamic>>?> get pageStartDocuments;
  Timer? get searchDebounce;
  set searchDebounce(Timer? value);
  Future<List<AdminUserData>>? get searchFuture;
  set searchFuture(Future<List<AdminUserData>>? value);
  String get searchText;
  set searchText(String value);
  int get pageIndex;
  set pageIndex(int value);
  AdminUserSortMode get sortMode;
  set sortMode(AdminUserSortMode value);
  AdminUsersContentActions get content;
  AdminUsersControllerActions get controller;
}

abstract interface class AdminUsersContentActions {
  Widget userTile(BuildContext context, AdminUserData user);
  Widget adminUserSearchField();
  Widget adminUserSearchResults();
  Widget userPageControls({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    required bool hasNextPage,
  });
}

abstract interface class AdminUsersControllerActions {
  void resetUserPages();
  void setBannedOnly(bool value);
  void setSortMode(AdminUserSortMode value);
  int compareAdminUsers(AdminUserData first, AdminUserData second);
  Query<Map<String, dynamic>> usersPageQuery();
  void queueAdminUserSearch(String value);
  Future<List<AdminUserData>> searchAdminUsers(String queryText);
  Future<bool> canManageUser(BuildContext context, AdminUserData user);
  bool canShowManagementActions(AdminUserData user);
  Future<Set<String>?> requestModeratorCountryCodes(
    BuildContext context,
    AdminUserData user,
  );
  Future<void> setModeratorStatus(
    BuildContext context,
    AdminUserData user,
    bool makeModerator,
  );
  Future<void> setCommunityModeratorStatus(
    BuildContext context,
    AdminUserData user,
    bool makeModerator,
  );
  Future<AdminBanInput?> requestBanInput(
    BuildContext context,
    AdminUserData user,
  );
  Future<void> banUser(BuildContext context, AdminUserData user);
  Future<void> unbanUser(BuildContext context, AdminUserData user);
  Future<void> deleteUser(BuildContext context, AdminUserData user);
  void handleUserAction(
    BuildContext context,
    AdminUserData user,
    String action,
  );
}
