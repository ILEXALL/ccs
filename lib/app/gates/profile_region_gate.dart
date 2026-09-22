import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserProfileRevision;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/profile/models/profile_validation.dart'
    show profileRegionIsComplete, requiredRegionMessage;
import 'package:ccs_app/features/profile/data/required_region.dart'
    show saveRequiredProfileRegion;
import 'package:ccs_app/shared/models/countries.dart'
    show
        allSupportedCountryNames,
        canonicalSpotCountryName,
        countryFlagEmoji,
        countryIsoCode,
        localizedCountryName;

class ProfileRegionGate extends StatefulWidget {
  final Widget child;
  final Future<void> Function(String city, String country) saveRegion;
  const ProfileRegionGate({
    super.key,
    required this.child,
    this.saveRegion = saveRequiredProfileRegion,
  });

  @override
  State<ProfileRegionGate> createState() => _ProfileRegionGateState();
}

class _ProfileRegionGateState extends State<ProfileRegionGate> {
  final formKey = GlobalKey<FormState>();
  late final cityController = TextEditingController(text: currentUser.city);
  late final countryController = TextEditingController(
    text: currentUser.country,
  );
  bool saving = false;
  String? saveError;

  @override
  void dispose() {
    cityController.dispose();
    countryController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await widget.saveRegion(
        cityController.text.trim(),
        countryIsoCode(countryController.text)!,
      );
      if (!mounted) return;
      setState(() => saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError = communityText(
          en: 'Could not save your region. Check your connection and try again.',
          ru: 'Не удалось сохранить регион. Проверьте подключение и попробуйте снова.',
          lv: 'Neizdevās saglabāt reģionu. Pārbaudiet savienojumu un mēģiniet vēlreiz.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: currentUserProfileRevision,
    builder: (context, _, child) {
      // Pending Firestore snapshots must not unlock the app before save succeeds.
      if (!saving &&
          saveError == null &&
          profileRegionIsComplete(currentUser.city, currentUser.country)) {
        return widget.child;
      }
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: Colors.black54,
          body: Center(
            child: AlertDialog(
              scrollable: true,
              title: CcsText(
                communityText(
                  en: 'Set your region',
                  ru: 'Укажите регион',
                  lv: 'Norādiet reģionu',
                ),
              ),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CcsText(requiredRegionMessage),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('profile-country'),
                        initialValue: countryIsoCode(countryController.text),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: communityText(
                            en: 'Country',
                            ru: 'Страна',
                            lv: 'Valsts',
                          ),
                          prefixIcon: const Icon(Icons.public, color: blue),
                        ),
                        items: allSupportedCountryNames()
                            .map(
                              (country) => DropdownMenuItem<String>(
                                value: countryIsoCode(country),
                                child: CcsText(
                                  countryFlagEmoji(country) +
                                      ' ' +
                                      localizedCountryName(country),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: saving
                            ? null
                            : (code) {
                                if (code != null)
                                  countryController.text =
                                      canonicalSpotCountryName(code);
                              },
                        validator: (value) =>
                            value == null ? requiredRegionMessage : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const ValueKey('profile-city'),
                        controller: cityController,
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: communityText(
                            en: 'City',
                            ru: 'Город',
                            lv: 'Pilsēta',
                          ),
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ||
                                (value ?? '').trim().length > 120
                            ? requiredRegionMessage
                            : null,
                      ),
                      if (saveError != null)
                        CcsText(
                          saveError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: saving ? null : save,
                  child: CcsText(
                    saving
                        ? trText('Saving...')
                        : communityText(
                            en: 'Save and continue',
                            ru: 'Сохранить и продолжить',
                            lv: 'Saglabāt un turpināt',
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
