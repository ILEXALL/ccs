import 'package:ccs_app/features/moderation/models/admin_user_sort.dart'
    show AdminUserSortMode;
import 'package:ccs_app/features/moderation/controllers/admin_users_view_state.dart';
import 'package:ccs_app/features/moderation/widgets/admin_users_content.dart';
import 'package:ccs_app/features/moderation/controllers/admin_users_controller.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/models/admin_user.dart'
    show AdminUserData;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class AdminUsersScreen extends StatefulWidget implements AdminUsersInputs {
  @override
  final bool initialBannedOnly;

  const AdminUsersScreen({super.key, this.initialBannedOnly = false});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with LanguageReactiveState
    implements AdminUsersViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  int get configUsersPerPage => usersPerPage;

  @override
  late final AdminUsersContentActions content = AdminUsersContent(this);

  @override
  late final AdminUsersControllerActions controller = AdminUsersController(
    this,
  );

  static const int usersPerPage = 25;

  @override
  late bool bannedOnly;
  @override
  final searchController = TextEditingController();
  @override
  final searchFocusNode = FocusNode();
  @override
  final pageStartDocuments = <DocumentSnapshot<Map<String, dynamic>>?>[null];
  @override
  Timer? searchDebounce;
  @override
  Future<List<AdminUserData>>? searchFuture;
  @override
  String searchText = '';
  @override
  int pageIndex = 0;
  @override
  AdminUserSortMode sortMode = AdminUserSortMode.recent;

  @override
  void initState() {
    super.initState();
    bannedOnly = widget.initialBannedOnly && userRoleIsStaff(currentUser.role);
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Users'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: controller.usersPageQuery().debugSnapshots(
          'admin: ${sortMode.name} users page ${pageIndex + 1}',
        ),
        builder: (context, snapshot) {
          final fetchedDocuments =
              snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final hasNextPage = fetchedDocuments.length > usersPerPage;
          final pageDocuments = fetchedDocuments.take(usersPerPage).toList();
          final allUsers = pageDocuments
              .map(AdminUserData.fromFirestore)
              .where((user) => !user.deleted)
              .toList();
          final canUseBannedList = userRoleIsStaff(currentUser.role);
          final users = bannedOnly
              ? allUsers.where((user) => user.banned).toList()
              : allUsers;
          users.sort(controller.compareAdminUsers);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              CcsText(
                bannedOnly ? 'Banned app users' : 'Users',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              CcsText(
                searchText.isNotEmpty
                    ? 'Suggestions appear as you type.'
                    : users.isEmpty
                    ? bannedOnly
                          ? trText('No banned users')
                          : 'No users yet.'
                    : '${users.length} user${users.length == 1 ? '' : 's'} on page ${pageIndex + 1}, sorted ${sortMode == AdminUserSortMode.recent ? 'by online and last seen' : 'alphabetically'}.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              if (canUseBannedList) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: CcsText(trText('All users')),
                        selected: !bannedOnly,
                        showCheckmark: false,
                        selectedColor: blue,
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        side: BorderSide(
                          color: !bannedOnly ? blue : Colors.white12,
                        ),
                        labelStyle: TextStyle(
                          color: !bannedOnly ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                        onSelected: (_) => controller.setBannedOnly(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: CcsText(trText('Banned app users')),
                        selected: bannedOnly,
                        showCheckmark: false,
                        selectedColor: Colors.redAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        side: BorderSide(
                          color: bannedOnly ? Colors.redAccent : Colors.white12,
                        ),
                        labelStyle: TextStyle(
                          color: bannedOnly ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                        onSelected: (_) => controller.setBannedOnly(true),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: CcsText(
                  'Sort users by',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: const CcsText('Online / recent'),
                      selected: sortMode == AdminUserSortMode.recent,
                      showCheckmark: false,
                      selectedColor: blue,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      side: BorderSide(
                        color: sortMode == AdminUserSortMode.recent
                            ? blue
                            : Colors.white12,
                      ),
                      labelStyle: TextStyle(
                        color: sortMode == AdminUserSortMode.recent
                            ? Colors.white
                            : Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) =>
                          controller.setSortMode(AdminUserSortMode.recent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      avatar: const Icon(Icons.sort_by_alpha, size: 18),
                      label: const CcsText('Alphabetical'),
                      selected: sortMode == AdminUserSortMode.alphabetical,
                      showCheckmark: false,
                      selectedColor: blue,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      side: BorderSide(
                        color: sortMode == AdminUserSortMode.alphabetical
                            ? blue
                            : Colors.white12,
                      ),
                      labelStyle: TextStyle(
                        color: sortMode == AdminUserSortMode.alphabetical
                            ? Colors.white
                            : Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                      onSelected: (_) => controller.setSortMode(
                        AdminUserSortMode.alphabetical,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              content.adminUserSearchField(),
              const SizedBox(height: 18),
              if (searchText.isNotEmpty)
                content.adminUserSearchResults()
              else if (snapshot.connectionState == ConnectionState.waiting &&
                  snapshot.data == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator(color: blue)),
                )
              else if (snapshot.hasError)
                EmptyStateCard(
                  icon: Icons.error_outline,
                  title: 'Could not load users',
                  text: '${snapshot.error}',
                )
              else if (users.isEmpty)
                EmptyStateCard(
                  icon: bannedOnly ? Icons.block : Icons.people_outline,
                  title: bannedOnly ? 'No banned users' : 'No users yet',
                  text: bannedOnly
                      ? 'Banned users will appear here.'
                      : 'Users will appear here after they sign in.',
                )
              else
                for (final user in users) ...[
                  content.userTile(context, user),
                  const SizedBox(height: 10),
                ],
              if (searchText.isEmpty && !snapshot.hasError) ...[
                const SizedBox(height: 8),
                content.userPageControls(
                  documents: pageDocuments,
                  hasNextPage: hasNextPage,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
