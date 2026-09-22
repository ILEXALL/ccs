import 'package:ccs_app/features/spots/models/explore_sort.dart';
import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart'
    show blue, ccsBlueCyanGradient, ccsGradientEnd;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotColorForCategory;
import 'package:ccs_app/features/spots/controllers/explore_view_state.dart';

/// Renders reusable sections for ExploreScreen.
class ExploreContent implements ExploreContentActions {
  final ExploreViewState host;
  ExploreContent(this.host);

  @override
  Widget sortChip(ExploreSortMode mode) {
    final selected = host.selectedMode == mode;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: CcsText(trText(exploreSortLabel(mode))),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) =>
            unawaited(host.controller.selectExploreSortMode(mode)),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: selected ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget savedFilterChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: const CcsText('Saved'),
        avatar: Icon(
          host.showSavedOnly ? Icons.bookmark : Icons.bookmark_border,
          color: host.showSavedOnly ? Colors.white : Colors.white70,
          size: 18,
        ),
        selected: host.showSavedOnly,
        showCheckmark: false,
        onSelected: (value) =>
            host.updateView(() => host.showSavedOnly = value),
        selectedColor: blue,
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        side: BorderSide(color: host.showSavedOnly ? blue : Colors.white12),
        labelStyle: TextStyle(
          color: host.showSavedOnly ? Colors.white : Colors.white70,
          fontWeight: host.showSavedOnly ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget sortPill(ExploreSortMode mode, IconData icon) {
    final selected = host.selectedMode == mode;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(host.controller.selectExploreSortMode(mode)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? ccsBlueCyanGradient : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ccsGradientEnd.withValues(alpha: 0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: CcsText(
                  trText(exploreSortLabel(mode)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget sortSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          sortPill(ExploreSortMode.popular, Icons.trending_up),
          sortPill(ExploreSortMode.newest, Icons.auto_awesome),
          sortPill(ExploreSortMode.nearest, Icons.near_me_outlined),
        ],
      ),
    );
  }

  @override
  Widget categorySelectionStrip(Map<String, int> counts) {
    final uniqueCategories = host.controller.orderedExploreCategories(counts);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - (host.configCategoryCardGap * 2)) / 3;
        final itemExtent = itemWidth + host.configCategoryCardGap;

        return SizedBox(
          height: 50,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              host.controller.snapCategoryStrip(itemExtent);
              return false;
            },
            child: ListView.builder(
              controller: host.categoryScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              itemCount: uniqueCategories.length,
              itemBuilder: (context, index) {
                final category = uniqueCategories[index];
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == uniqueCategories.length - 1
                        ? 0
                        : host.configCategoryCardGap,
                  ),
                  child: categorySelectionButton(
                    category: category,
                    count: counts[category] ?? 0,
                    width: itemWidth,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget categorySelectionButton({
    required String category,
    required int count,
    required double width,
  }) {
    final selected = host.selectedExploreCategory == category;
    final color = category == host.configUpcomingCategoryName
        ? Colors.orangeAccent
        : spotColorForCategory(category);

    return InkWell(
      onTap: () {
        host.updateView(() {
          host.selectedExploreCategory = category;
          host.userSelectedExploreCategory = true;
          host.pendingSpotsEntryDefaultCategory = false;
        });
      },
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.060 : 0.035),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.10),
            width: selected ? 1.45 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.16),
                    blurRadius: 10,
                    spreadRadius: 0.2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.050),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                host.controller.spotCategoryMaterialIcon(category),
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CcsText(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 0),
                  CcsText(
                    '$count',
                    style: TextStyle(
                      color: selected ? Colors.white70 : Colors.white38,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
