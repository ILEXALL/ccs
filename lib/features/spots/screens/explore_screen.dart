import 'package:ccs_app/features/spots/models/explore_sort.dart';
import 'package:ccs_app/features/spots/controllers/explore_view_state.dart';
import 'package:ccs_app/features/spots/widgets/explore_content.dart';
import 'package:ccs_app/features/spots/controllers/explore_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/spots/widgets/spots_interaction_guide.dart';
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/events/widgets/upcoming_events.dart'
    show UpcomingTemporarySpotsSection;
import 'package:ccs_app/features/partners/widgets/partners_header_button.dart'
    show PartnersHeaderButton;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots, spotCategoryFilters, spotCountryFilters;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/widgets/explore_spot_card.dart'
    show ExploreSpotCard;
import 'package:ccs_app/features/spots/widgets/feed_header.dart'
    show
        SpotsHeaderIconButton,
        SpotsHeaderLanguageButton,
        SpotsHeaderNotificationButton;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsAppBarLogo;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class ExploreScreen extends StatefulWidget implements ExploreInputs {
  @override
  final bool isVisible;

  const ExploreScreen({super.key, this.isVisible = true});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    implements ExploreViewState {
  @override
  void updateView(VoidCallback update) => setState(update);

  @override
  String get configUpcomingCategoryName => upcomingCategoryName;

  @override
  double get configCategoryCardGap => _categoryCardGap;

  @override
  late final ExploreContentActions content = ExploreContent(this);

  @override
  late final ExploreControllerActions controller = ExploreController(this);

  @override
  ExploreSortMode selectedMode = ExploreSortMode.popular;
  @override
  LatLng? nearestSortLocation;
  @override
  bool nearestSortLocationLoading = false;
  @override
  bool showSavedOnly = false;
  @override
  String searchQuery = '';
  @override
  String selectedExploreCategory = '';
  @override
  bool userSelectedExploreCategory = false;
  @override
  late final ScrollController categoryScrollController;
  @override
  late final ScrollController spotCardScrollController;
  @override
  final Set<String> expandedCategories = {};
  @override
  Timer? temporarySpotRefreshTimer;
  @override
  Timer? nextTemporarySpotExpiryTimer;
  @override
  bool pendingSpotsEntryDefaultCategory = true;

  @override
  void initState() {
    super.initState();
    categoryScrollController = ScrollController();
    spotCardScrollController = ScrollController();
    savedSpots.addListener(controller.refreshSavedFilter);
    spotCategoryFilters.addListener(controller.refreshSpotCategoryFilters);
    spotCountryFilters.addListener(controller.refreshSpotCategoryFilters);
    appUiPreferences.addListener(controller.refreshLanguageLabels);
    // Events can expire or reveal their location without a Firestore
    // update. Refresh the Spots tab so the temporary card removes expired spots
    // and updates availability labels while the user stays on this screen.
    temporarySpotRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => controller.refreshTemporarySpots(),
    );
    controller.scheduleNextTemporarySpotRefresh();
  }

  @override
  void dispose() {
    temporarySpotRefreshTimer?.cancel();
    nextTemporarySpotExpiryTimer?.cancel();
    categoryScrollController.dispose();
    spotCardScrollController.dispose();
    savedSpots.removeListener(controller.refreshSavedFilter);
    spotCategoryFilters.removeListener(controller.refreshSpotCategoryFilters);
    spotCountryFilters.removeListener(controller.refreshSpotCategoryFilters);
    appUiPreferences.removeListener(controller.refreshLanguageLabels);
    super.dispose();
  }

  static const String upcomingCategoryName = upcomingEventsCategoryName;
  static const double _categoryCardGap = 8;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: reviewSpots,
      builder: (context, _, _) {
        final upcomingSpots = controller.upcomingTemporarySpots();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            controller.scheduleNextTemporarySpotRefresh();
          }
        });
        final categoryCounts = controller.visibleCategoryCounts(
          approvedPublicSpots(),
          upcomingCount: upcomingSpots.length,
        );
        controller.normalizeSelectedExploreCategory(categoryCounts);

        final approvedSpots = controller.filteredSpots();
        final feedSpots = selectedExploreCategory == upcomingCategoryName
            ? upcomingSpots
            : controller.sortedSpots(approvedSpots);

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 68,
            titleSpacing: 12,
            backgroundColor: Colors.transparent,
            foregroundColor: blue,
            title: Row(
              children: [
                const SizedBox(
                  width: 60,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CcsAppBarLogo(),
                  ),
                ),
                const SizedBox(width: 7),
                const Expanded(child: PartnersHeaderButton()),
                const SizedBox(width: 7),
                SpotsHeaderIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: trText('Spot filters'),
                  onTap: controller.showExploreCategoryFilterSheet,
                ),
                const SizedBox(width: 5),
                const SpotsHeaderLanguageButton(),
                const SizedBox(width: 5),
                const SpotsHeaderNotificationButton(),
              ],
            ),
          ),
          body: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    onChanged: (value) => setState(() => searchQuery = value),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: trText('Search spots...'),
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white54,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.045),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: const BorderSide(color: blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  content.sortSegmentedControl(),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SpotsInteractionGuide(
                      categorySlider: content.categorySelectionStrip(
                        categoryCounts,
                      ),
                      categoryController: categoryScrollController,
                      cardsController: spotCardScrollController,
                      hasCards: feedSpots.isNotEmpty,
                      isVisible: widget.isVisible,
                      translate: trText,
                      cards: Builder(
                        builder: (context) {
                          if (selectedExploreCategory == upcomingCategoryName) {
                            final groups = controller
                                .upcomingTemporarySpotGroups();
                            return RefreshIndicator(
                              onRefresh: controller.refreshUpcomingSpotFeed,
                              color: blue,
                              child: ListView(
                                controller: spotCardScrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.only(bottom: 14),
                                children: [
                                  if (groups.isEmpty)
                                    EmptyStateCard(
                                      icon: Icons.event_available_outlined,
                                      title: trText('No upcoming spots'),
                                      text: trText(
                                        'No upcoming spots match your filters. Check countries, saved-only mode, or search. Pull down to refresh.',
                                      ),
                                    )
                                  else
                                    UpcomingTemporarySpotsSection(
                                      groups: groups,
                                    ),
                                ],
                              ),
                            );
                          }

                          if (feedSpots.isEmpty) {
                            return EmptyStateCard(
                              icon: Icons.explore,
                              title: approvedPublicSpots().isEmpty
                                  ? 'No spots here yet'
                                  : 'No spots in this category',
                              text: approvedPublicSpots().isEmpty
                                  ? 'Approved spots will appear here after moderation.'
                                  : 'Choose another category or update your search.',
                            );
                          }

                          final cards = <Widget>[
                            for (final spot in feedSpots)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ExploreSpotCard(spot: spot),
                              ),
                          ];

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final itemExtent = constraints.maxHeight / 3;

                              return NotificationListener<
                                ScrollEndNotification
                              >(
                                onNotification: (_) {
                                  controller.snapSpotCards(itemExtent);
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: spotCardScrollController,
                                  physics: const BouncingScrollPhysics(
                                    parent: AlwaysScrollableScrollPhysics(),
                                  ),
                                  padding: EdgeInsets.zero,
                                  itemExtent: itemExtent,
                                  itemCount: cards.length,
                                  itemBuilder: (context, index) => cards[index],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
