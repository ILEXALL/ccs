import 'package:ccs_app/features/spots/models/explore_sort.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

abstract interface class ExploreInputs {
  bool get isVisible;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class ExploreViewState {
  BuildContext get context;
  bool get mounted;
  ExploreInputs get widget;
  void updateView(VoidCallback update);
  ExploreSortMode get selectedMode;
  set selectedMode(ExploreSortMode value);
  LatLng? get nearestSortLocation;
  set nearestSortLocation(LatLng? value);
  bool get nearestSortLocationLoading;
  set nearestSortLocationLoading(bool value);
  bool get showSavedOnly;
  set showSavedOnly(bool value);
  String get searchQuery;
  set searchQuery(String value);
  String get selectedExploreCategory;
  set selectedExploreCategory(String value);
  bool get userSelectedExploreCategory;
  set userSelectedExploreCategory(bool value);
  ScrollController get categoryScrollController;
  ScrollController get spotCardScrollController;
  Set<String> get expandedCategories;
  Timer? get temporarySpotRefreshTimer;
  set temporarySpotRefreshTimer(Timer? value);
  Timer? get nextTemporarySpotExpiryTimer;
  set nextTemporarySpotExpiryTimer(Timer? value);
  bool get pendingSpotsEntryDefaultCategory;
  set pendingSpotsEntryDefaultCategory(bool value);
  String get configUpcomingCategoryName;
  double get configCategoryCardGap;
  ExploreContentActions get content;
  ExploreControllerActions get controller;
}

abstract interface class ExploreContentActions {
  Widget sortChip(ExploreSortMode mode);
  Widget savedFilterChip();
  Widget sortPill(ExploreSortMode mode, IconData icon);
  Widget sortSegmentedControl();
  Widget categorySelectionStrip(Map<String, int> counts);
  Widget categorySelectionButton({
    required String category,
    required int count,
    required double width,
  });
}

abstract interface class ExploreControllerActions {
  void refreshSavedFilter();
  void refreshSpotCategoryFilters();
  void refreshLanguageLabels();
  void refreshTemporarySpots();
  void scheduleNextTemporarySpotRefresh();
  void toggleCategoryExpansion(String category);
  List<CarSpot> sortedSpots(List<CarSpot> spots);
  List<CarSpot> filteredSpots();
  List<CarSpot> upcomingTemporarySpots();
  Map<String, List<CarSpot>> upcomingTemporarySpotGroups();
  Future<void> refreshUpcomingSpotFeed();
  Map<String, List<CarSpot>> groupedSpotsByCategory(List<CarSpot> spots);
  Future<void> showExploreCategoryFilterSheet();
  Future<void> selectExploreSortMode(ExploreSortMode mode);
  Map<String, int> visibleCategoryCounts(
    List<CarSpot> spots, {
    int upcomingCount = 0,
  });
  List<String> orderedExploreCategories(Map<String, int> counts);
  void normalizeSelectedExploreCategory(Map<String, int> counts);
  IconData spotCategoryMaterialIcon(String category);
  void snapCategoryStrip(double itemExtent);
  void snapSpotCards(double itemExtent);
}
