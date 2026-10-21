import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/moderation/data/spot_review_filters.dart'
    show adminReviewCountryCodes;
import 'package:ccs_app/shared/models/countries.dart'
    show countryFlagEmoji, localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class ReviewCountriesScreen extends StatefulWidget {
  const ReviewCountriesScreen({super.key, required this.selectedCountries});

  final Set<String> selectedCountries;

  @override
  State<ReviewCountriesScreen> createState() => _ReviewCountriesScreenState();
}

class _ReviewCountriesScreenState extends State<ReviewCountriesScreen>
    with LanguageReactiveState {
  late final selected = {...widget.selectedCountries};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const CcsText('Review countries')),
      body: ValueListenableBuilder(
        valueListenable: maintenanceModeConfig,
        builder: (context, _, _) {
          final countries = adminReviewCountryCodes();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (currentUser.role == UserRole.admin)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CcsText(
                    'Selected countries also control spot review notifications.',
                  ),
                ),
              if (countries.isEmpty)
                const CcsText('No available countries assigned'),
              for (final code in countries)
                CheckboxListTile(
                  secondary: CcsText(countryFlagEmoji(code)),
                  title: CcsText(localizedCountryName(code)),
                  value: selected.contains(code),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selected.add(code);
                    } else {
                      selected.remove(code);
                    }
                  }),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(selected.intersection(adminReviewCountryCodes().toSet())),
          child: const CcsText('Apply selection'),
        ),
      ),
    );
  }
}
