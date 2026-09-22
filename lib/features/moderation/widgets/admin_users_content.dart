import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/models/admin_user.dart'
    show AdminUserData;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;
import 'package:ccs_app/shared/widgets/user_badge.dart' show UserPrimaryBadge;
import 'package:ccs_app/features/moderation/controllers/admin_users_view_state.dart';

/// Renders reusable sections for AdminUsersScreen.
class AdminUsersContent implements AdminUsersContentActions {
  final AdminUsersViewState host;
  AdminUsersContent(this.host);

  @override
  Widget userTile(BuildContext context, AdminUserData user) {
    final statusColor = user.banActive
        ? Colors.redAccent
        : user.appearsOnline
        ? Colors.greenAccent
        : user.verified
        ? blue
        : Colors.white54;
    final canManage = host.controller.canShowManagementActions(user);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              user.banActive
                  ? Icons.block
                  : user.appearsOnline
                  ? Icons.circle
                  : user.verified
                  ? Icons.verified
                  : Icons.person_outline,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => openUserProfile(
                context,
                uid: user.uid,
                fallbackUsername: user.username,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: CcsText(
                            user.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        UserPrimaryBadge(
                          role: user.role,
                          verified: user.verified,
                          globalChatModerator: user.globalChatModerator,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    CcsText(
                      user.email.isEmpty ? user.name : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 5),
                    CcsText(
                      user.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (user.role == UserRole.moderator) ...[
                      const SizedBox(height: 4),
                      CcsText(
                        user.moderatorCountryCodes.isEmpty
                            ? trText('No countries assigned')
                            : user.moderatorCountryCodes
                                  .map(
                                    (code) =>
                                        '${countryFlagEmoji(code)} ${localizedCountryName(code)}',
                                  )
                                  .join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (user.banActive && user.banReason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      CcsText(
                        user.banReason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: panelGlass,
            iconColor: Colors.white70,
            onSelected: (action) =>
                host.controller.handleUserAction(context, user, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'open',
                child: CcsText(trText('Open profile')),
              ),
              const PopupMenuDivider(),
              if (canManage) ...[
                PopupMenuItem(
                  value: 'ban',
                  child: CcsText(
                    trText(user.banActive ? 'Update ban' : 'Ban user'),
                  ),
                ),
                if (user.banned)
                  PopupMenuItem(
                    value: 'unban',
                    child: CcsText(trText('Unban')),
                  ),
              ] else
                PopupMenuItem(
                  enabled: false,
                  child: CcsText(trText('Protected account')),
                ),
              if (currentUser.role == UserRole.admin && canManage) ...[
                const PopupMenuDivider(),
                if (user.role == UserRole.user)
                  PopupMenuItem(
                    value: 'make_moderator',
                    child: CcsText(trText('Make moderator')),
                  ),
                if (user.role == UserRole.moderator)
                  PopupMenuItem(
                    value: 'edit_moderator_countries',
                    child: CcsText(trText('Edit moderator countries')),
                  ),
                if (user.role == UserRole.moderator)
                  PopupMenuItem(
                    value: 'remove_moderator',
                    child: CcsText(trText('Remove moderator')),
                  ),
                if (!user.globalChatModerator)
                  PopupMenuItem(
                    value: 'make_community_moderator',
                    child: CcsText(trText('Make community moderator')),
                  ),
                if (user.globalChatModerator)
                  PopupMenuItem(
                    value: 'remove_community_moderator',
                    child: CcsText(trText('Remove community moderator')),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: CcsText(
                    trText('Delete user'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget adminUserSearchField() {
    return TextField(
      controller: host.searchController,
      focusNode: host.searchFocusNode,
      onChanged: host.controller.queueAdminUserSearch,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search username',
        prefixIcon: const Icon(Icons.search, color: blue),
        suffixIcon: host.searchText.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  host.searchController.clear();
                  host.controller.queueAdminUserSearch('');
                  host.searchFocusNode.requestFocus();
                },
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
      ),
    );
  }

  @override
  Widget adminUserSearchResults() {
    final future = host.searchFuture;
    if (future == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: blue)),
      );
    }

    return FutureBuilder<List<AdminUserData>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: blue)),
          );
        }

        if (snapshot.hasError) {
          return EmptyStateCard(
            icon: Icons.search_off,
            title: 'Search failed',
            text: '${snapshot.error}',
          );
        }

        final users = snapshot.data ?? const <AdminUserData>[];
        if (users.isEmpty) {
          return const EmptyStateCard(
            icon: Icons.person_search,
            title: 'No users found',
            text: 'Try another username.',
          );
        }

        return Column(
          children: [
            for (final user in users) ...[
              userTile(context, user),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget userPageControls({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
    required bool hasNextPage,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: host.pageIndex == 0
                ? null
                : () => host.updateView(() => host.pageIndex--),
            icon: const Icon(Icons.chevron_left),
            label: const CcsText('Previous'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: CcsText(
            'Page ${host.pageIndex + 1}',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: !hasNextPage || documents.isEmpty
                ? null
                : () {
                    final nextPageStart = documents.last;
                    host.updateView(() {
                      if (host.pageStartDocuments.length ==
                          host.pageIndex + 1) {
                        host.pageStartDocuments.add(nextPageStart);
                      } else {
                        host.pageStartDocuments[host.pageIndex + 1] =
                            nextPageStart;
                      }
                      host.pageIndex++;
                    });
                  },
            icon: const Icon(Icons.chevron_right),
            label: const CcsText('Next'),
          ),
        ),
      ],
    );
  }
}
