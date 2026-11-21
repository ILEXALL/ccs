import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions, spotColorForCategory;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName, spotCountryKey;

Widget spotFilterColumns({
  required BuildContext context,
  required Set<String> enabledCategories,
  required Set<String> enabledCountries,
  required List<String> countries,
  required VoidCallback onChanged,
}) {
  Widget toggle({
    required String title,
    required bool value,
    required Widget icon,
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    activeThumbColor: Colors.white,
    activeTrackColor: blue,
    inactiveTrackColor: const Color(0xFF323B49),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    secondary: icon,
    title: CcsText(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  return DefaultTabController(
    length: 2,
    child: SizedBox(
      height: math.min(480.0, MediaQuery.sizeOf(context).height * .58),
      child: Material(
        color: const Color(0xFF1B222D),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TabBar(
              indicatorColor: blue,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(text: trText('Categories')),
                Tab(text: trText('Countries with spots')),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: CcsText(
                                '${enabledCategories.length} / ${spotCategoryOptions.length}',
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                enabledCategories
                                  ..clear()
                                  ..addAll(spotCategoryOptions);
                                onChanged();
                              },
                              child: const CcsText('Select all'),
                            ),
                            TextButton(
                              onPressed: () {
                                enabledCategories.clear();
                                onChanged();
                              },
                              child: const CcsText('Clear'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final category in spotCategoryOptions)
                              toggle(
                                title: trText(category),
                                value: enabledCategories.contains(category),
                                icon: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: spotColorForCategory(category),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                onChanged: (enabled) {
                                  if (enabled) {
                                    enabledCategories.add(category);
                                  } else {
                                    enabledCategories.remove(category);
                                  }
                                  onChanged();
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    children: [
                      for (final country in countries)
                        toggle(
                          title: localizedCountryName(country),
                          icon: CcsText(
                            countryFlagEmoji(country),
                            style: const TextStyle(fontSize: 22),
                          ),
                          value: enabledCountries
                              .map(spotCountryKey)
                              .contains(spotCountryKey(country)),
                          onChanged: (enabled) {
                            final selected = enabledCountries
                                .map(spotCountryKey)
                                .contains(spotCountryKey(country));
                            if (!enabled &&
                                selected &&
                                enabledCountries
                                        .map(spotCountryKey)
                                        .toSet()
                                        .length ==
                                    1)
                              return;
                            enabledCountries.removeWhere(
                              (value) =>
                                  spotCountryKey(value) ==
                                  spotCountryKey(country),
                            );
                            if (enabled) enabledCountries.add(country);
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
