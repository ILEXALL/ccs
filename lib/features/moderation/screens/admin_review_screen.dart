import 'package:ccs_app/features/moderation/screens/review_countries_screen.dart';
import 'package:ccs_app/features/moderation/data/moderation_api.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/features/moderation/controllers/spot_batch_review.dart';
import 'package:ccs_app/features/moderation/data/submit_spot_review_decision.dart';
import 'package:ccs_app/features/moderation/data/spot_review_lease.dart';
import 'package:ccs_app/features/moderation/screens/admin_edit_spot_screen.dart';
import 'package:ccs_app/features/moderation/widgets/batch_spot_review_card.dart';
import 'package:ccs_app/features/spots/models/spot_status.dart';
import 'package:ccs_app/features/moderation/screens/admin_rewards_screen.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show spotsCollection, userReportsCollection, usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/screens/firestore_debug_screen.dart'
    show FirestoreDebugScreen;
import 'package:ccs_app/features/moderation/data/spot_review_filters.dart'
    show
        AdminSpotFilter,
        adminReviewCountryCodes,
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
    show countryFlagEmoji, countryIsoCode, localizedCountryName;
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
    with LanguageReactiveState, WidgetsBindingObserver {
  AdminSpotFilter selectedFilter = AdminSpotFilter.pending;
  final batch = SpotBatchReview();
  bool editing = false, savingCountries = false, countriesLoaded = false;
  final selectedCountries = <String>{};
  final countryLeases = <String, SpotReviewLease>{};
  final acquiringCountries = <String>{};

  void countryLeaseChanged() {
    if (mounted) setState(() {});
  }

  Future<void> loadCountries() async {
    try {
      final available = adminReviewCountryCodes().toSet();
      if (currentUser.role == UserRole.admin) {
        final doc = await usersCollection().doc(currentUser.uid).get();
        final saved = doc.data()?['adminSpotReviewCountryCodes'];
        if (saved is List) {
          selectedCountries.addAll(
            saved.whereType<String>().where(available.contains),
          );
        } else {
          final own = countryIsoCode(currentUser.country);
          if (own != null && available.contains(own))
            selectedCountries.add(own);
          await sendModerationAction({
            'action': 'spot_review_countries',
            'countryCodes': selectedCountries.toList(),
          });
        }
      } else {
        selectedCountries.addAll(available);
      }
      if (!mounted) return;
      setState(() => countriesLoaded = true);
      await Future.wait(selectedCountries.toList().map(acquireCountry));
    } catch (_) {
      if (mounted) setState(() => countriesLoaded = false);
    }
  }

  Future<void> acquireCountry(String code) async {
    if (!mounted || acquiringCountries.contains(code)) return;
    countryLeases.remove(code)
      ?..removeListener(countryLeaseChanged)
      ..dispose();
    final lease = SpotReviewLease.country(code);
    countryLeases[code] = lease;
    lease.addListener(countryLeaseChanged);
    setState(() => acquiringCountries.add(code));
    try {
      await lease.acquire();
    } catch (error) {
      lease.markLost(error: error, opening: true);
    }
    if (mounted) setState(() => acquiringCountries.remove(code));
  }

  Future<void> selectReviewCountries() async {
    if (batch.busy || editing || savingCountries || !countriesLoaded) return;
    final result = await Navigator.of(context).push<Set<String>>(
      appPageRoute(
        builder: (_) =>
            ReviewCountriesScreen(selectedCountries: selectedCountries),
      ),
    );
    if (!mounted || result == null) return;
    await updateCountries(result);
  }

  Future<void> updateCountries(Set<String> selection) async {
    if (batch.busy || editing || savingCountries) return;
    final next = selection.intersection(adminReviewCountryCodes().toSet());
    final added = next.difference(selectedCountries);
    final removed = selectedCountries.difference(next);
    if (added.isEmpty && removed.isEmpty) return;
    setState(() => savingCountries = true);
    try {
      if (currentUser.role == UserRole.admin) {
        await sendModerationAction({
          'action': 'spot_review_countries',
          'countryCodes': next.toList(),
        });
      }
      if (!mounted) return;
      setState(() {
        selectedCountries
          ..clear()
          ..addAll(next);
      });
      for (final code in removed) {
        countryLeases.remove(code)
          ?..removeListener(countryLeaseChanged)
          ..dispose();
        for (final d in batch.drafts.values.toList()) {
          if (d.spot.effectiveCountryCode == code) batch.clear(d.spot.id);
        }
      }
      await Future.wait(added.map(acquireCountry));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: CcsText('Could not save countries. Please try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => savingCountries = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    for (final lease in countryLeases.values) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        lease.suspend();
        if (!batch.busy && !editing) unawaited(lease.release());
      } else if (state == AppLifecycleState.resumed) {
        unawaited(lease.resume());
      }
    }
  }

  Future<void> editSpot(CarSpot spot) async {
    final countryLease = countryLeases[spot.effectiveCountryCode];
    if (batch.busy || editing || countryLease?.active != true) return;
    batch.clear(spot.id);
    setState(() => editing = true);
    final lease = SpotReviewLease(
      spot.id,
      countrySessionId: countryLease!.sessionId,
    );
    try {
      if (!await lease.acquire()) {
        throw StateError(trText('Another reviewer has this spot open.'));
      }
      final doc = await spotsCollection()
          .doc(spot.id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) throw StateError(trText('Spot is no longer available'));
      if (!mounted) return;
      await openAdminEditSpot(
        context,
        CarSpot.fromFirestore(doc),
        reviewLease: lease,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CcsText(
              lease.reviewerUsername.isNotEmpty
                  ? '${trText('Currently being reviewed by')} @${lease.reviewerUsername}'
                  : trText('Could not open spot review. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      lease.dispose();
      if (mounted) setState(() => editing = false);
    }
  }

  Future<void> submitDecisions() async {
    FocusScope.of(context).unfocus();
    final count = await batch.submit((decision) async {
      final lease = countryLeases[decision.spot.effectiveCountryCode];
      if (lease == null || !lease.active)
        throw StateError(
          'Country review is not active. Try again to continue.',
        );
      await lease.ensureActive();
      await submitSpotReviewDecision(
        decision,
        countrySessionId: lease.sessionId,
      );
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: CcsText(
          '${trText('Decisions submitted')}: $count. ${batch.errors.isEmpty ? '' : trText('Check the marked cards and try again.')}',
        ),
      ),
    );
  }

  Future<void> confirmExit() async {
    if (batch.busy || editing) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const CcsText('Discard review decisions?'),
        content: const CcsText('Your decisions have not been submitted yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const CcsText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const CcsText('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      batch.drafts.clear();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(loadCountries());
    if (userRoleIsStaff(currentUser.role)) startAdminReviewSpotSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final lease in countryLeases.values) {
      lease.removeListener(countryLeaseChanged);
      lease.dispose();
    }
    batch.dispose();
    unawaited(stopAdminReviewSpotSync());
    super.dispose();
  }

  Widget filterChip(AdminSpotFilter filter, Set<String> codes) {
    final selected = selectedFilter == filter;
    final count = codes.fold<int>(
      0,
      (sum, code) => sum + adminSpotCount(filter, countryCode: code),
    );

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([batch, maintenanceModeConfig]),
    builder: (context, _) => PopScope(
      canPop: !batch.busy && !editing && batch.drafts.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(confirmExit());
      },
      child: buildPanel(context),
    ),
  );

  Widget buildPanel(BuildContext context) {
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
      bottomNavigationBar: batch.drafts.isEmpty && !batch.busy
          ? null
          : SafeArea(
              child: Container(
                color: const Color(0xff111923),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CcsText(
                      '${trText('Approve')}: ${batch.drafts.values.where((d) => d.status == SpotStatus.approved).length}  ·  ${trText('Reject')}: ${batch.drafts.values.where((d) => d.status == SpotStatus.rejected).length}',
                    ),
                    CcsText(
                      batch.drafts.values
                          .map((d) => d.spot.effectiveCountryCode)
                          .toSet()
                          .map(localizedCountryName)
                          .join(' · '),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    if (!batch.busy)
                      TextButton(
                        onPressed: editing
                            ? null
                            : () {
                                for (final id in batch.drafts.keys.toList()) {
                                  batch.clear(id);
                                }
                              },
                        child: const CcsText('Clear decisions'),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: batch.busy || editing || savingCountries
                            ? null
                            : submitDecisions,
                        icon: batch.busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.done_all),
                        label: CcsText(
                          batch.busy
                              ? '${trText('Processing decision...')} ${batch.completed}/${batch.total}'
                              : '${trText('Submit decisions')} (${batch.drafts.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: AbsorbPointer(
        absorbing: batch.busy || editing,
        child: ValueListenableBuilder<List<CarSpot>>(
          valueListenable: reviewSpots,
          builder: (context, _, _) {
            final countries = adminReviewCountryCodes();
            final codes = selectedCountries.intersection(countries.toSet());
            final filteredSpots = adminSpotsForFilter(selectedFilter)
                .where(
                  (spot) =>
                      codes.contains(spot.effectiveCountryCode) &&
                      countryLeases[spot.effectiveCountryCode]?.active == true,
                )
                .toList();
            for (final draft in batch.drafts.values) {
              if (codes.contains(draft.spot.effectiveCountryCode) &&
                  countryLeases[draft.spot.effectiveCountryCode]?.active ==
                      true &&
                  batch.errors.containsKey(draft.spot.id) &&
                  !filteredSpots.any((s) => s.id == draft.spot.id))
                filteredSpots.add(draft.spot);
            }
            final label = adminSpotFilterLabel(selectedFilter).toLowerCase();

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
                  sliver: SliverList.list(
                    children: [
                      if (editing) const LinearProgressIndicator(),
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
                        style: const TextStyle(
                          color: Colors.white54,
                          height: 1.35,
                        ),
                      ),
                      if (currentUser.role == UserRole.moderator) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: blue.withValues(alpha: 0.35),
                            ),
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
                      ExpansionTile(
                        title: const CcsText('Panel tools'),
                        children: [
                          if (currentUser.role == UserRole.admin) ...[
                            ProfileActionTile(
                              icon: Icons.cloud_outlined,
                              title: 'Firestore usage',
                              subtitle: 'View activity and estimated charges',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  appPageRoute(
                                    builder: (_) =>
                                        const FirestoreDebugScreen(),
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
                                appPageRoute(
                                  builder: (_) => const AdminUsersScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: userReportsCollection()
                                .where('status', isEqualTo: 'open')
                                .limit(50)
                                .debugSnapshots(
                                  'admin: open user reports badge listener',
                                ),
                            builder: (context, reportSnapshot) {
                              final openReports =
                                  reportSnapshot.data?.docs.length ?? 0;
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
                                      builder: (_) =>
                                          const AdminUserReportsScreen(),
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
                                  builder: (_) => const AdminUsersScreen(
                                    initialBannedOnly: true,
                                  ),
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
                                      final doc = await spotsCollection()
                                          .doc(id)
                                          .get();
                                      if (!context.mounted || !doc.exists) {
                                        return;
                                      }
                                      final spot = CarSpot.fromFirestore(doc);
                                      Navigator.push(
                                        context,
                                        appPageRoute(
                                          builder: (_) =>
                                              SpotDetailScreen(spot: spot),
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
                                    builder: (_) =>
                                        const AdminRegionalRestrictionsScreen(),
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
                                appPageRoute(
                                  builder: (_) => const ForumModerationScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!countriesLoaded)
                        OutlinedButton(
                          onPressed: loadCountries,
                          child: const CcsText('Load review countries'),
                        ),
                      if (savingCountries) const LinearProgressIndicator(),
                      if (countries.isEmpty)
                        const CcsText('No available countries assigned'),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.public, color: blue),
                        title: const CcsText('Review countries'),
                        subtitle: CcsText(
                          codes.isEmpty
                              ? trText('Select countries')
                              : codes
                                    .map(
                                      (code) =>
                                          '${countryFlagEmoji(code)} ${localizedCountryName(code)}',
                                    )
                                    .join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: countriesLoaded && !savingCountries,
                        onTap: countriesLoaded && !savingCountries
                            ? selectReviewCountries
                            : null,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            filterChip(AdminSpotFilter.pending, codes),
                            filterChip(AdminSpotFilter.edited, codes),
                            filterChip(AdminSpotFilter.approved, codes),
                            filterChip(AdminSpotFilter.rejected, codes),
                            filterChip(AdminSpotFilter.all, codes),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                for (final code in codes.where(
                  (code) => countryLeases[code]?.active != true,
                ))
                  SliverToBoxAdapter(
                    child: Card(
                      child: ListTile(
                        leading: acquiringCountries.contains(code)
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.lock_outline),
                        title: CcsText(localizedCountryName(code)),
                        subtitle: CcsText(
                          countryLeases[code]?.reviewerUsername.isNotEmpty ==
                                  true
                              ? '${trText('Country is being reviewed by')} @${countryLeases[code]!.reviewerUsername}'
                              : trText(
                                  'Country review is not active. Try again to continue.',
                                ),
                        ),
                        trailing: acquiringCountries.contains(code)
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () => acquireCountry(code),
                              ),
                      ),
                    ),
                  ),
                if (filteredSpots.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: EmptyStateCard(
                        icon: Icons.admin_panel_settings,
                        title: adminEmptyTitle(selectedFilter),
                        text: adminEmptyText(selectedFilter),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                  sliver: SliverList.builder(
                    itemCount: filteredSpots.length,
                    itemBuilder: (context, index) {
                      final spot = filteredSpots[index];
                      final draft = batch.drafts[spot.id];
                      return Padding(
                        key: ValueKey(spot.id),
                        padding: const EdgeInsets.only(bottom: 12),
                        child:
                            spot.status == SpotStatus.pending ||
                                spot.status == SpotStatus.edited ||
                                draft != null
                            ? BatchSpotReviewCard(
                                spot: spot,
                                decision: draft?.status,
                                reason: draft?.reason ?? '',
                                error: batch.errors[spot.id],
                                onEdit: () => editSpot(spot),
                                onDecision: (status) =>
                                    batch.select(spot, status),
                                onReason: (text) => batch.reason(spot.id, text),
                                onClear: () => batch.clear(spot.id),
                              )
                            : AdminSpotTile(
                                spot: spot,
                                countrySessionId:
                                    countryLeases[spot.effectiveCountryCode]
                                        ?.sessionId,
                              ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
