import 'package:ccs_app/features/events/models/upcoming_events.dart';
import 'package:ccs_app/features/spots/models/explore_sort.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters, safeLatLngFromPosition;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show
        approvedPublicSpots,
        availableSpotCountries,
        cleanSpotCountries,
        localizedSpotFilterSummary,
        spotCategoryFilters,
        spotCountryFilters,
        spotMatchesSelectedCountries,
        updateSpotCategoryFilters,
        updateSpotCountryFilters;
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart' show savedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show refreshFirebaseSpotsFromServer;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions;
import 'package:ccs_app/features/spots/widgets/spot_filter_panel.dart'
    show spotFilterColumns;
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart'
    show primarySpotCategory;
import 'package:ccs_app/features/spots/controllers/explore_view_state.dart';

/// Coordinates actions and data loading for ExploreScreen.
class ExploreController implements ExploreControllerActions {
  final ExploreViewState host;
  ExploreController(this.host);

  @override
  void refreshSavedFilter() {
    if (host.mounted && host.showSavedOnly) {
      host.updateView(() {});
    }
  }

  @override
  void refreshSpotCategoryFilters() {
    if (host.mounted) {
      host.updateView(() {});
    }
  }

  @override
  void refreshLanguageLabels() {
    if (host.mounted) {
      host.updateView(() {});
    }
  }

  @override
  void refreshTemporarySpots() {
    if (!host.mounted) {
      return;
    }

    if (approvedPublicSpots().any((spot) => spot.hasTemporaryWindow)) {
      host.updateView(() {});
    }

    scheduleNextTemporarySpotRefresh();
  }

  @override
  void scheduleNextTemporarySpotRefresh() {
    host.nextTemporarySpotExpiryTimer?.cancel();

    final now = DateTime.now().millisecondsSinceEpoch;
    final nextAt = approvedPublicSpots()
        .where((spot) => spot.hasTemporaryWindow)
        .expand<int>((spot) sync* {
          final startsAt = spot.startsAtMillis;
          final expiresAt = spot.expiresAtMillis;
          final revealAt = spot.effectiveShowOnMapAtMillis;
          if (revealAt != null && revealAt > now) yield revealAt;
          if (startsAt != null && startsAt > now) yield startsAt;
          if (expiresAt != null && expiresAt > now) yield expiresAt;
        })
        .fold<int?>(null, (best, value) {
          if (best == null || value < best) {
            return value;
          }
          return best;
        });

    if (nextAt == null) {
      return;
    }

    final delay = Duration(milliseconds: nextAt - now + 150);
    host.nextTemporarySpotExpiryTimer = Timer(delay, refreshTemporarySpots);
  }

  @override
  void toggleCategoryExpansion(String category) {
    host.updateView(() {
      if (!host.expandedCategories.add(category)) {
        host.expandedCategories.remove(category);
      }
    });
  }

  @override
  List<CarSpot> sortedSpots(List<CarSpot> spots) {
    final list = [...spots];

    switch (host.selectedMode) {
      case ExploreSortMode.popular:
        list.sort((a, b) {
          final likesCompare = b.likeCount.compareTo(a.likeCount);
          if (likesCompare != 0) {
            return likesCompare;
          }
          return b.createdAtMillis.compareTo(a.createdAtMillis);
        });
        break;
      case ExploreSortMode.newest:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
      case ExploreSortMode.nearest:
        final location = host.nearestSortLocation;
        if (location == null) {
          // Until location is available, keep the feed stable instead of doing
          // an incorrect distance sort. The location request starts when the
          // user taps Nearest.
          list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        } else {
          list.sort((a, b) {
            final distanceCompare = distanceBetweenLatLngMeters(
              location,
              a.coordinates,
            ).compareTo(distanceBetweenLatLngMeters(location, b.coordinates));
            if (distanceCompare != 0) {
              return distanceCompare;
            }
            return b.createdAtMillis.compareTo(a.createdAtMillis);
          });
        }
        break;
      case ExploreSortMode.meet:
        list.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
        break;
    }

    return list;
  }

  @override
  List<CarSpot> filteredSpots() {
    final selectedCategory = host.selectedExploreCategory;
    final query = host.searchQuery.trim().toLowerCase();

    return approvedPublicSpots().where((spot) {
      if (!spotMatchesSelectedCountries(spot)) {
        return false;
      }
      if (spot.isExpired) {
        return false;
      }

      // Temporary spots/events live only inside the Upcoming category so the
      // same card is not duplicated under Photo, Meet, Food, etc.
      if (spot.hasTemporaryWindow) {
        return false;
      }

      if (selectedCategory == host.configUpcomingCategoryName) {
        return false;
      }

      if (!spot.categories.contains(selectedCategory)) {
        return false;
      }

      if (host.showSavedOnly &&
          !savedSpots.value.any((saved) => isSameSpot(saved, spot))) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        spot.name,
        spot.cityCountry,
        spot.description,
        spot.addedBy,
        ...spot.categories,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  @override
  List<CarSpot> upcomingTemporarySpots() {
    final query = host.searchQuery.trim().toLowerCase();
    final spots = approvedPublicSpots().where((spot) {
      if (!spot.isGroupSpot && !spotMatchesSelectedCountries(spot)) {
        return false;
      }
      if (!spot.hasTemporaryWindow || spot.isExpired) {
        return false;
      }

      if (host.showSavedOnly &&
          !savedSpots.value.any((saved) => isSameSpot(saved, spot))) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        spot.name,
        spot.cityCountry,
        spot.description,
        spot.addedBy,
        host.configUpcomingCategoryName,
        ...spot.categories,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();

    spots.sort((a, b) {
      final aActive = a.isTemporaryActiveNow;
      final bActive = b.isTemporaryActiveNow;
      if (aActive != bActive) {
        return aActive ? -1 : 1;
      }
      return (a.startsAtMillis ?? a.createdAtMillis).compareTo(
        b.startsAtMillis ?? b.createdAtMillis,
      );
    });

    return spots;
  }

  @override
  Map<String, List<CarSpot>> upcomingTemporarySpotGroups() {
    return groupUpcomingTemporarySpots(upcomingTemporarySpots());
  }

  @override
  Future<void> refreshUpcomingSpotFeed() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    try {
      await refreshFirebaseSpotsFromServer().timeout(
        const Duration(seconds: 20),
      );
      if ((host.mounted && viewContext.mounted)) host.updateView(() {});
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) return;
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          content: CcsText(
            trText('Could not refresh spots. Please try again.'),
          ),
        ),
      );
    }
  }

  @override
  Map<String, List<CarSpot>> groupedSpotsByCategory(List<CarSpot> spots) {
    final grouped = <String, List<CarSpot>>{};

    for (final category in spotCategoryOptions) {
      final categorySpots = spots
          .where((spot) => primarySpotCategory(spot) == category)
          .toList();
      final sortedCategorySpots = sortedSpots(categorySpots);

      if (sortedCategorySpots.isNotEmpty) {
        grouped[category] = sortedCategorySpots;
      }
    }

    return grouped;
  }

  @override
  Future<void> showExploreCategoryFilterSheet() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final nextEnabledCategories = Set<String>.from(spotCategoryFilters.value);
    final availableCountries = availableSpotCountries();
    final nextEnabledCountries = cleanSpotCountries(spotCountryFilters.value);
    if (nextEnabledCountries.isEmpty && availableCountries.isNotEmpty) {
      final ownCountry = cleanSpotCountries(<String>{currentUser.country});
      nextEnabledCountries.add(
        ownCountry.isNotEmpty ? ownCountry.first : availableCountries.first,
      );
    }

    await showModalBottomSheet<void>(
      context: viewContext,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;
            final selectedCountryCount = nextEnabledCountries.length;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: CcsText(
                            'Explore filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      localizedSpotFilterSummary(
                        selectedCategories: selectedCount,
                        totalCategories: spotCategoryOptions.length,
                        selectedCountries: selectedCountryCount,
                      ),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    spotFilterColumns(
                      context: context,
                      enabledCategories: nextEnabledCategories,
                      enabledCountries: nextEnabledCountries,
                      countries: availableCountries,
                      onChanged: () => setSheetState(() {}),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          updateSpotCategoryFilters(nextEnabledCategories);
                          unawaited(
                            updateSpotCountryFilters(nextEnabledCountries),
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const CcsText(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Future<void> selectExploreSortMode(ExploreSortMode mode) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (mode != ExploreSortMode.nearest) {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.selectedMode = mode);
      }
      return;
    }

    if ((host.mounted && viewContext.mounted)) {
      host.updateView(() {
        host.selectedMode = mode;
        host.nearestSortLocationLoading = true;
      });
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if ((host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: Colors.orangeAccent,
              content: CcsText(
                trText('Location permission is needed for distance.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if ((host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: Colors.orangeAccent,
              content: CcsText(
                trText('Turn on phone location to show distance.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      final location = safeLatLngFromPosition(position);
      if (location == null) {
        return;
      }

      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.nearestSortLocation = location);
      }
    } catch (error) {
      debugPrint('Nearest spots location failed: $error');
      if ((host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orangeAccent,
            content: CcsText(
              trText('Could not get your location.'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.nearestSortLocationLoading = false);
      }
    }
  }

  @override
  Map<String, int> visibleCategoryCounts(
    List<CarSpot> spots, {
    int upcomingCount = 0,
  }) {
    final counts = <String, int>{
      for (final category in spotCategoryOptions)
        category: spots
            .where(
              (spot) =>
                  !spot.isExpired &&
                  spotMatchesSelectedCountries(spot) &&
                  !spot.hasTemporaryWindow &&
                  spot.categories.contains(category) &&
                  (!host.showSavedOnly ||
                      savedSpots.value.any((saved) => isSameSpot(saved, spot))),
            )
            .length,
    };

    if (upcomingCount > 0) {
      counts[host.configUpcomingCategoryName] = upcomingCount;
    }

    return counts;
  }

  @override
  List<String> orderedExploreCategories(Map<String, int> counts) {
    final hasUpcoming = (counts[host.configUpcomingCategoryName] ?? 0) > 0;
    final normalCategories =
        spotCategoryOptions
            .where((category) => (counts[category] ?? 0) > 0)
            .toList()
          ..sort((first, second) {
            final countCompare = (counts[second] ?? 0).compareTo(
              counts[first] ?? 0,
            );
            if (countCompare != 0) {
              return countCompare;
            }
            return spotCategoryOptions
                .indexOf(first)
                .compareTo(spotCategoryOptions.indexOf(second));
          });

    if (hasUpcoming) {
      return [host.configUpcomingCategoryName, ...normalCategories];
    }

    // With no upcoming events, Photo is always the first/default chamber even
    // when it currently has zero results. Keep the remaining populated
    // categories after it, and keep Upcoming reachable at the far end.
    return [
      'Photo',
      ...normalCategories.where((category) => category != 'Photo'),
      host.configUpcomingCategoryName,
    ];
  }

  @override
  void normalizeSelectedExploreCategory(Map<String, int> counts) {
    final categories = orderedExploreCategories(counts);
    final hasUpcoming = (counts[host.configUpcomingCategoryName] ?? 0) > 0;
    final defaultCategory = hasUpcoming
        ? host.configUpcomingCategoryName
        : 'Photo';

    if (host.pendingSpotsEntryDefaultCategory) {
      host.selectedExploreCategory = defaultCategory;
      host.userSelectedExploreCategory = false;

      // If the feed is still completely empty, keep this pending so the first
      // real Firestore snapshot can still promote Upcoming to the true default.
      // Once any approved spot data exists, the entry default is settled.
      if (approvedPublicSpots().isNotEmpty) {
        host.pendingSpotsEntryDefaultCategory = false;
      }
      return;
    }

    if (categories.isEmpty) {
      host.selectedExploreCategory = 'Photo';
      host.userSelectedExploreCategory = false;
      return;
    }

    if (!categories.contains(host.selectedExploreCategory)) {
      host.selectedExploreCategory = defaultCategory;
      host.userSelectedExploreCategory = false;
    }
  }

  @override
  IconData spotCategoryMaterialIcon(String category) {
    switch (category) {
      case upcomingEventsCategoryName:
        return Icons.event_available_outlined;
      case 'Drift':
        return Icons.sports_motorsports;
      case 'Photo':
        return Icons.photo_camera_outlined;
      case 'Meet':
        return Icons.groups_2_outlined;
      case 'Drive':
        return Icons.route_outlined;
      case 'Service':
        return Icons.build_outlined;
      case 'Detailing':
        return Icons.auto_fix_high_outlined;
      case 'Wash':
        return Icons.local_car_wash_outlined;
      case 'Store':
        return Icons.shopping_bag_outlined;
      case 'Drag':
        return Icons.speed_outlined;
      case 'Track':
        return Icons.sports_score_outlined;
      case 'Activity':
        return Icons.confirmation_number_outlined;
      case 'Off-road':
        return Icons.terrain_outlined;
      case 'Food':
        return Icons.restaurant_outlined;
      case 'Scrap':
        return Icons.car_repair_outlined;
    }

    return Icons.local_offer_outlined;
  }

  @override
  void snapCategoryStrip(double itemExtent) {
    if (!host.categoryScrollController.hasClients || itemExtent <= 0) {
      return;
    }

    final position = host.categoryScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }

    final current = position.pixels;
    final target = (current / itemExtent).round() * itemExtent;
    final clampedTarget = target
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    if ((clampedTarget - current).abs() < 1.5) {
      return;
    }

    unawaited(
      host.categoryScrollController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void snapSpotCards(double itemExtent) {
    if (!host.spotCardScrollController.hasClients || itemExtent <= 0) {
      return;
    }

    final position = host.spotCardScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }

    final current = position.pixels;
    final target = (current / itemExtent).round() * itemExtent;
    final clampedTarget = target
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    if ((clampedTarget - current).abs() < 2.5) {
      return;
    }

    unawaited(
      host.spotCardScrollController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
