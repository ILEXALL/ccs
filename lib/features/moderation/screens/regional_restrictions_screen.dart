import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig, maintenanceModeDocument, refreshMaintenanceMode;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/shared/models/countries.dart'
    show
        allSupportedCountryNames,
        countryFlagEmoji,
        countryIsoCode,
        countryRestrictionKeys,
        localizedCountryName;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

class AdminRegionalRestrictionsScreen extends StatefulWidget {
  const AdminRegionalRestrictionsScreen({super.key});

  @override
  State<AdminRegionalRestrictionsScreen> createState() =>
      _AdminRegionalRestrictionsScreenState();
}

class _AdminRegionalRestrictionsScreenState
    extends State<AdminRegionalRestrictionsScreen> {
  late Set<String> selectedCountryCodes;
  String searchQuery = '';
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    selectedCountryCodes = {...maintenanceModeConfig.value.bannedCountryCodes};
  }

  Future<void> saveRestrictions() async {
    if (isSaving || currentUser.role != UserRole.admin) return;
    setState(() => isSaving = true);

    try {
      final config = maintenanceModeConfig.value;
      final codes = selectedCountryCodes.toList(growable: false)..sort();
      await maintenanceModeDocument().debugSet({
        'maintenanceEnabled': config.maintenanceEnabled,
        'maintenanceTitle': config.maintenanceTitle,
        'maintenanceMessage': config.maintenanceMessage,
        'allowAdminBypass': config.allowAdminBypass,
        'minimumAppVersion': config.minimumAppVersion,
        'updateContact': config.updateContact,
        'bannedCountryCodes': codes,
        'bannedCountryKeys': countryRestrictionKeys(selectedCountryCodes),
      }, SetOptions(merge: true));
      await refreshMaintenanceMode();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Regional restrictions updated.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            '${trText('Could not update regional restrictions')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser.role != UserRole.admin) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CcsText('No access', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final query = searchQuery.trim().toLowerCase();
    final countries = allSupportedCountryNames()
        .where((country) {
          if (query.isEmpty) return true;
          return localizedCountryName(country).toLowerCase().contains(query) ||
              country.toLowerCase().contains(query);
        })
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Regional restrictions'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panelGlass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: CcsText(
                      'Users in selected countries can use CCS, but cannot add spots or share live location.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setState(() => searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: trText('Search countries'),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            CcsText(
              '${selectedCountryCodes.length} ${trText('restricted countries')}',
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                itemCount: countries.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 54,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final country = countries[index];
                  final code = countryIsoCode(country)!;
                  final selected = selectedCountryCodes.contains(code);
                  return Material(
                    color: selected
                        ? Colors.redAccent.withValues(alpha: 0.14)
                        : panelGlass,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => setState(() {
                        if (!selectedCountryCodes.add(code)) {
                          selectedCountryCodes.remove(code);
                        }
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? Colors.redAccent : Colors.white12,
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              activeColor: Colors.redAccent,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) => setState(() {
                                if (!selectedCountryCodes.add(code)) {
                                  selectedCountryCodes.remove(code);
                                }
                              }),
                            ),
                            CcsText(
                              countryFlagEmoji(country),
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: CcsText(
                                localizedCountryName(country),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : saveRestrictions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: CcsText(isSaving ? 'Saving...' : 'Save restrictions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
