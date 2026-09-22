import 'package:ccs_app/features/moderation/screens/admin_rewards_screen.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show spotsCollection, userReportsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/debug_preferences.dart'
    show firestoreDebugButtonVisible, saveFirestoreDebugButtonPreference;
import 'package:ccs_app/features/moderation/data/spot_review_filters.dart'
    show
        AdminSpotFilter,
        adminEmptyText,
        adminEmptyTitle,
        adminSpotCount,
        adminSpotFilterLabel,
        adminSpotsForFilter;
import 'package:ccs_app/features/moderation/screens/admin_users_screen.dart'
    show AdminUsersScreen;
import 'package:ccs_app/features/moderation/screens/forum_moderation_screen.dart'
    show ForumModerationScreen;
import 'package:ccs_app/features/moderation/screens/regional_restrictions_screen.dart'
    show AdminRegionalRestrictionsScreen;
import 'package:ccs_app/features/moderation/screens/user_reports_screen.dart'
    show AdminUserReportsScreen;
import 'package:ccs_app/features/moderation/widgets/admin_spot_tile.dart'
    show AdminSpotTile;
import 'package:ccs_app/features/profile/widgets/profile_action_tile.dart'
    show ProfileActionTile;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show startAdminReviewSpotSync, stopAdminReviewSpotSync;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen>
    with LanguageReactiveState {
  AdminSpotFilter selectedFilter = AdminSpotFilter.pending;

  @override
  void initState() {
    super.initState();
    if (userRoleIsStaff(currentUser.role)) startAdminReviewSpotSync();
  }

  @override
  void dispose() {
    unawaited(stopAdminReviewSpotSync());
    super.dispose();
  }

  Widget filterChip(AdminSpotFilter filter) {
    final selected = selectedFilter == filter;
    final count = adminSpotCount(filter);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: CcsText('${adminSpotFilterLabel(filter)} $count'),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => selectedFilter = filter),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!userRoleIsStaff(currentUser.role)) {
      return const Scaffold(body: Center(child: CcsText('No access')));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(
          currentUser.role == UserRole.admin
              ? 'Admin Panel'
              : 'Moderator Panel',
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ValueListenableBuilder<List<CarSpot>>(
        valueListenable: reviewSpots,
        builder: (context, _, _) {
          final filteredSpots = adminSpotsForFilter(selectedFilter);
          final label = adminSpotFilterLabel(selectedFilter).toLowerCase();

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              CcsText(
                currentUser.role == UserRole.admin
                    ? 'Admin Review'
                    : 'Moderator Review',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              CcsText(
                filteredSpots.isEmpty
                    ? 'No $label spots right now.'
                    : '${filteredSpots.length} $label spot${filteredSpots.length == 1 ? '' : 's'} in Firebase.',
                style: const TextStyle(color: Colors.white54, height: 1.35),
              ),
              if (currentUser.role == UserRole.moderator) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: blue.withValues(alpha: 0.35)),
                  ),
                  child: CcsText(
                    currentUser.moderatorCountryCodes.isEmpty
                        ? trText('No countries assigned')
                        : '${trText('Your assigned countries')}: ${currentUser.moderatorCountryCodes.map((code) => '${countryFlagEmoji(code)} ${localizedCountryName(code)}').join(' • ')}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (currentUser.role == UserRole.admin) ...[
                ValueListenableBuilder<bool>(
                  valueListenable: firestoreDebugButtonVisible,
                  builder: (context, debugVisible, _) {
                    return Material(
                      color: panelGlass,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Colors.white12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile.adaptive(
                        value: debugVisible,
                        activeColor: blue,
                        contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                        secondary: const Icon(
                          Icons.bug_report_outlined,
                          color: blue,
                        ),
                        title: const CcsText(
                          'Debug mode',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: const CcsText(
                          'Show or hide the Firestore debug bug button',
                          style: TextStyle(color: Colors.white54),
                        ),
                        onChanged: (value) {
                          unawaited(saveFirestoreDebugButtonPreference(value));
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],
              ProfileActionTile(
                icon: Icons.people_alt,
                title: 'Users',
                subtitle:
                    'Search profiles, verify users, ban, unban, or delete',
                onTap: () {
                  Navigator.push(
                    context,
                    appPageRoute(builder: (_) => const AdminUsersScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: userReportsCollection()
                    .where('status', isEqualTo: 'open')
                    .limit(50)
                    .debugSnapshots('admin: open user reports badge listener'),
                builder: (context, reportSnapshot) {
                  final openReports = reportSnapshot.data?.docs.length ?? 0;
                  return ProfileActionTile(
                    icon: Icons.report_outlined,
                    title: openReports > 0
                        ? 'User reports ($openReports)'
                        : 'User reports',
                    subtitle: openReports > 0
                        ? '$openReports open profile report${openReports == 1 ? '' : 's'} waiting'
                        : 'Review profile reports from users',
                    onTap: () {
                      Navigator.push(
                        context,
                        appPageRoute(
                          builder: (_) => const AdminUserReportsScreen(),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
              ProfileActionTile(
                icon: Icons.block,
                title: 'Banned app users',
                subtitle: 'Open banned users and remove bans',
                onTap: () {
                  Navigator.push(
                    context,
                    appPageRoute(
                      builder: (_) =>
                          const AdminUsersScreen(initialBannedOnly: true),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              if (currentUser.role == UserRole.admin) ...[
                ProfileActionTile(
                  icon: Icons.card_giftcard,
                  title: achievementText(
                    appUiPreferences.language.name,
                    'Rewards',
                    'Награды',
                    'Atlīdzības',
                  ),
                  subtitle: achievementText(
                    appUiPreferences.language.name,
                    'Create bonus tasks',
                    'Создать дополнительные задания',
                    'Izveidot papildu uzdevumus',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute(
                      builder: (_) => AdminRewardsScreen(
                        language: appUiPreferences.language.name,
                        request: xpScreenRequest,
                        onOpenSpot: (id) async {
                          final doc = await spotsCollection().doc(id).get();
                          if (!context.mounted || !doc.exists) return;
                          final spot = CarSpot.fromFirestore(doc);
                          Navigator.push(
                            context,
                            appPageRoute(
                              builder: (_) => SpotDetailScreen(spot: spot),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ProfileActionTile(
                  icon: Icons.public_off_outlined,
                  title: 'Regional restrictions',
                  subtitle:
                      'Restrict Add Spot and live-location sharing by country',
                  color: Colors.orangeAccent,
                  onTap: () {
                    Navigator.push(
                      context,
                      appPageRoute(
                        builder: (_) => const AdminRegionalRestrictionsScreen(),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 10),
              ProfileActionTile(
                icon: Icons.forum_outlined,
                title: '📝 Форум',
                subtitle: 'Проверить новые темы форума',
                onTap: () {
                  Navigator.push(
                    context,
                    appPageRoute(builder: (_) => const ForumModerationScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    filterChip(AdminSpotFilter.pending),
                    filterChip(AdminSpotFilter.edited),
                    filterChip(AdminSpotFilter.approved),
                    filterChip(AdminSpotFilter.rejected),
                    filterChip(AdminSpotFilter.all),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (filteredSpots.isEmpty)
                EmptyStateCard(
                  icon: Icons.admin_panel_settings,
                  title: adminEmptyTitle(selectedFilter),
                  text: adminEmptyText(selectedFilter),
                )
              else
                for (final spot in filteredSpots) ...[
                  AdminSpotTile(spot: spot),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}
