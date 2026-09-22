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
  Widget panel({required Widget child}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  return SizedBox(
    height: math.min(430.0, MediaQuery.sizeOf(context).height * 0.48),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: panel(
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: CcsText(
                            'Categories',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                          tooltip: trText('Select all'),
                          onPressed: () {
                            enabledCategories
                              ..clear()
                              ..addAll(spotCategoryOptions);
                            onChanged();
                          },
                          icon: const Icon(
                            Icons.done_all,
                            color: blue,
                            size: 19,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                          tooltip: trText('Clear'),
                          onPressed: () {
                            enabledCategories.clear();
                            onChanged();
                          },
                          icon: const Icon(
                            Icons.clear_all,
                            color: Colors.white54,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    itemCount: spotCategoryOptions.length,
                    itemBuilder: (context, index) {
                      final category = spotCategoryOptions[index];
                      return CheckboxListTile(
                        value: enabledCategories.contains(category),
                        onChanged: (enabled) {
                          if (enabled == true) {
                            enabledCategories.add(category);
                          } else {
                            enabledCategories.remove(category);
                          }
                          onChanged();
                        },
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        activeColor: spotColorForCategory(category),
                        checkColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: spotColorForCategory(category),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: CcsText(
                                category,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: panel(
            child: Column(
              children: [
                const SizedBox(
                  height: 56,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CcsText(
                        'Countries with spots',
                        maxLines: 2,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    itemCount: countries.length,
                    itemBuilder: (context, index) {
                      final country = countries[index];
                      final selected = enabledCountries
                          .map(spotCountryKey)
                          .contains(spotCountryKey(country));
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (enabled) {
                          enabledCountries.removeWhere(
                            (value) =>
                                spotCountryKey(value) ==
                                spotCountryKey(country),
                          );
                          if (enabled == true) {
                            enabledCountries.add(country);
                          } else if (enabledCountries.isEmpty) {
                            enabledCountries.add(country);
                          }
                          onChanged();
                        },
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        activeColor: blue,
                        checkColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: CcsText(
                          '${countryFlagEmoji(country)}  ${localizedCountryName(country)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
