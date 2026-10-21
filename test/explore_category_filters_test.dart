import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/spots/controllers/explore_controller.dart';
import 'package:ccs_app/features/spots/controllers/explore_view_state.dart';
import 'package:ccs_app/features/spots/data/spot_filters.dart';

class Host implements ExploreViewState {
  @override
  String get configUpcomingCategoryName => 'Events';
  @override
  bool pendingSpotsEntryDefaultCategory = false;
  @override
  bool userSelectedExploreCategory = true;
  @override
  String selectedExploreCategory = 'Photo';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final original = spotCategoryFilters.value;
  tearDown(() => spotCategoryFilters.value = original);
  test('category buttons follow filters, including enabled empty categories', () {
    final controller = ExploreController(Host());
    spotCategoryFilters.value = {'Food', 'Wash'};
    expect(controller.orderedExploreCategories({'Photo': 100, 'Food': 2}),
        ['Food', 'Wash', 'Events']);
    spotCategoryFilters.value = {'Photo', 'Food'};
    expect(controller.orderedExploreCategories({'Food': 2}),
        ['Photo', 'Food', 'Events']);
  });
  test('disabled active category falls back to a visible button', () {
    final host = Host();
    final controller = ExploreController(host);
    spotCategoryFilters.value = {'Wash'};
    controller.normalizeSelectedExploreCategory({'Photo': 100, 'Wash': 1});
    expect(host.selectedExploreCategory, 'Wash');
    spotCategoryFilters.value = {};
    controller.normalizeSelectedExploreCategory({});
    expect(host.selectedExploreCategory, 'Events');
  });
}
