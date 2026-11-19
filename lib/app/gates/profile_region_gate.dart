import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show signOutCurrentAccount;
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
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
    show saveRequiredProfileRegion, reloadRequiredProfileRegion;
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
  final Future<void> Function() loadProfile;
  final Duration operationTimeout;
  final Future<void> Function() signOut;
  const ProfileRegionGate({
    super.key,
    required this.child,
    this.saveRegion = saveRequiredProfileRegion,
    this.loadProfile = reloadRequiredProfileRegion,
    this.signOut = signOutCurrentAccount,
    this.operationTimeout = const Duration(seconds: 20),
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
  bool loading = false;
  String? loadError;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    if (currentUser.uid.isEmpty ||
        !profileRegionIsComplete(currentUser.city, currentUser.country)) {
      unawaited(loadProfile());
    }
  }

  Future<void> loadProfile() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await widget.loadProfile().timeout(widget.operationTimeout);
      if (!mounted) return;
      cityController.text = currentUser.city;
      countryController.text = currentUser.country;
      setState(() {
        loading = false;
        saveError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError =
            'Could not load your profile. Check your connection and retry.${error is FirebaseException ? ' (${error.code})' : ''}';
      });
    }
  }

  String? saveError;

  @override
  void dispose() {
    cityController.dispose();
    countryController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (loading || saving || !(formKey.currentState?.validate() ?? false))
      return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await widget
          .saveRegion(
            cityController.text.trim(),
            countryIsoCode(countryController.text)!,
          )
          .timeout(widget.operationTimeout);
      if (!mounted) return;
      setState(() => saving = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        saving = false;
        saveError =
            error is FirebaseException && error.code == 'permission-denied'
            ? 'Your profile update was denied. Retry loading your profile or sign in again. If this continues, contact support (permission-denied).'
            : error is FirebaseException && error.code == 'not-found'
            ? 'Your profile could not be found. Sign in again to restore your account.'
            : error is FirebaseException && error.code == 'unauthenticated'
            ? 'Your sign-in session could not be restored. Reload your profile or sign out and sign in again.'
            : communityText(
                    en: 'Could not save your region. Check your connection and try again.',
                    ru: 'Не удалось сохранить регион. Проверьте подключение и попробуйте снова.',
                    lv: 'Neizdevās saglabāt reģionu. Pārbaudiet savienojumu un mēģiniet vēlreiz.',
                  ) +
                  (error is FirebaseException ? ' (${error.code})' : '');
      });
    }
  }

  Future<void> signOut() async {
    try {
      await widget.signOut();
    } catch (_) {
      if (mounted)
        setState(() => loadError = 'Could not sign out. Please retry.');
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: currentUserProfileRevision,
    builder: (context, _, child) {
      if (loading || loadError != null) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            body: Center(
              child: AlertDialog(
                title: const CcsText('Loading your profile'),
                content: loading
                    ? const SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : CcsText(loadError!),
                actions: [
                  TextButton(
                    onPressed: signOut,
                    child: const CcsText('Sign out'),
                  ),
                  if (!loading)
                    TextButton(
                      onPressed: loadProfile,
                      child: const CcsText('Retry'),
                    ),
                ],
              ),
            ),
          ),
        );
      }
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
                if (!saving)
                  TextButton(
                    onPressed: signOut,
                    child: const CcsText('Sign out'),
                  ),
                if (saveError != null)
                  TextButton(
                    onPressed: saving ? null : loadProfile,
                    child: const CcsText('Reload profile'),
                  ),
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
