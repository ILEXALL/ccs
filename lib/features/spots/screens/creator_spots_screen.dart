import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/progression/widgets/leaderboard_widgets.dart'
    show creatorSpotsQuery, creatorSpotsText, qualifiesPermanentCreatedSpot;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart' show SpotPhoto;
import 'package:ccs_app/shared/models/countries.dart' show localizedCountryName;

class CreatorSpotsScreen extends StatefulWidget {
  final String uid;
  final String username;
  const CreatorSpotsScreen({
    super.key,
    required this.uid,
    required this.username,
  });

  @override
  State<CreatorSpotsScreen> createState() => _CreatorSpotsScreenState();
}

class _CreatorSpotsScreenState extends State<CreatorSpotsScreen>
    with LanguageReactiveState {
  final List<CarSpot> spots = [];
  bool loading = false;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      failed = false;
      if (refresh) {
        spots.clear();
      }
    });
    try {
      // Match the counter's legacy-owner fallback and permanent-spot policy.
      // Filter optional flags locally so old documents without isTemporary or
      // deleted are included. Exhaust pages even if a page has no eligible spots.
      final byId = <String, CarSpot>{};
      for (final legacyOwner in [false, true]) {
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        while (true) {
          var query = creatorSpotsQuery(
            widget.uid,
            legacyOwner: legacyOwner,
          ).orderBy(FieldPath.documentId).limit(100);
          if (cursor != null) query = query.startAfterDocument(cursor);
          final page = await query.debugGet(
            null,
            'profile: creator permanent spots page',
          );
          if (!mounted) return;
          for (final doc in page.docs) {
            if (qualifiesPermanentCreatedSpot(doc.data(), widget.uid)) {
              byId[doc.id] = CarSpot.fromFirestore(doc);
            }
          }
          if (page.docs.length < 100) break;
          cursor = page.docs.last;
        }
      }
      setState(() {
        spots
          ..clear()
          ..addAll(byId.values);
      });
    } catch (error) {
      debugPrint('Creator spots could not load: $error');
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(title: CcsText('${trText('Spots')} · ${widget.username}')),
    body: RefreshIndicator(
      onRefresh: () => load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final spot in spots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: panelGlass,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: SpotPhoto(
                    spot: spot,
                    width: 52,
                    height: 52,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: CcsText(spot.name),
                  subtitle: CcsText(spot.cityCountry),
                  trailing: const Icon(Icons.chevron_right, color: blue),
                  onTap: () => Navigator.push(
                    context,
                    appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
                  ),
                ),
              ),
            ),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (failed)
            TextButton(
              onPressed: () => load(),
              child: CcsText(trText('Try again')),
            )
          else if (spots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: CcsText(
                creatorSpotsText(
                  'No spots available to show yet.',
                  'Пока нет доступных спотов.',
                  'Pagaidām nav pieejamu vietu.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    ),
  );
}

String profileCountLabel(
  int count, {
  bool spots = false,
  AppLanguage? language,
}) {
  final lang = language ?? appUiPreferences.language;
  final one = count % 10 == 1 && count % 100 != 11;
  final few =
      count % 10 >= 2 &&
      count % 10 <= 4 &&
      (count % 100 < 12 || count % 100 > 14);
  final noun = switch (lang) {
    AppLanguage.en =>
      spots ? (count == 1 ? 'spot' : 'spots') : (count == 1 ? 'car' : 'cars'),
    AppLanguage.ru =>
      spots
          ? (one
                ? 'спот'
                : few
                ? 'спота'
                : 'спотов')
          : (one
                ? 'машина'
                : few
                ? 'машины'
                : 'машин'),
    AppLanguage.lv => spots ? (one ? 'vieta' : 'vietas') : 'auto',
  };
  return '$count $noun';
}

String localizedProfileLocation(
  String city,
  String country, {
  AppLanguage? language,
}) {
  final lang = language ?? appUiPreferences.language;
  final cityName = ['riga', 'rīga', 'рига'].contains(city.trim().toLowerCase())
      ? switch (lang) {
          AppLanguage.en => 'Riga',
          AppLanguage.ru => 'Рига',
          AppLanguage.lv => 'Rīga',
        }
      : city.trim();
  return [
    cityName,
    localizedCountryName(country, language: lang),
  ].where((part) => part.isNotEmpty).join(', ');
}
