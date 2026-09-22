import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart'
    show blue, panelGlass, policeAlertColor, sosAlertColor;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show mapFocusRequest;
import 'package:ccs_app/features/map/models/map_style.dart'
    show
        CcsMapStyle,
        ccsAdaptiveMapStylePreferenceKey,
        ccsMapStylePreferenceKey,
        mapStyleForLocalTime;
import 'package:ccs_app/features/map/data/map_overview.dart'
    show loadedSpotsMapCenter;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show
        availableSpotCountries,
        cleanSpotCountries,
        localizedSpotFilterSummary,
        spotCategoryFilters,
        spotCountryFilters,
        spotMatchesSelectedCountries,
        updateSpotCategoryFilters,
        updateSpotCountryFilters;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions;
import 'package:ccs_app/features/spots/screens/spot_detail_screen.dart'
    show SpotDetailScreen;
import 'package:ccs_app/features/spots/widgets/spot_filter_panel.dart'
    show spotFilterColumns;
import 'map_session.dart';

/// Coordinates appearance behavior using screen-owned state and lifecycle.
class MapAppearanceController implements MapAppearanceActions {
  final MapSession host;
  MapAppearanceController(this.host);

  @override
  Future<void> loadMapStylePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStyle = prefs.getString(ccsMapStylePreferenceKey);
      final savedManualStyle = CcsMapStyle.values.firstWhere(
        (style) => style.name == savedStyle,
        orElse: () => CcsMapStyle.dark,
      );
      final nextAdaptiveMapStyleEnabled =
          prefs.getBool(ccsAdaptiveMapStylePreferenceKey) ?? false;
      final nextStyle = nextAdaptiveMapStyleEnabled
          ? mapStyleForLocalTime(DateTime.now())
          : savedManualStyle;

      if (!host.mounted ||
          (nextStyle == host.mapStyle &&
              nextAdaptiveMapStyleEnabled == host.adaptiveMapStyleEnabled)) {
        return;
      }

      host.updateMap(() {
        host.mapStyle = nextStyle;
        host.adaptiveMapStyleEnabled = nextAdaptiveMapStyleEnabled;
      });
    } catch (_) {}
  }

  @override
  Future<void> setMapStyle(CcsMapStyle value) async {
    if (value == host.mapStyle && !host.adaptiveMapStyleEnabled) {
      return;
    }

    host.updateMap(() {
      host.mapStyle = value;
      host.adaptiveMapStyleEnabled = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ccsMapStylePreferenceKey, value.name);
      await prefs.setBool(ccsAdaptiveMapStylePreferenceKey, false);
    } catch (_) {}
  }

  @override
  Future<void> setAdaptiveMapStyle(bool enabled) async {
    final nextStyle = enabled
        ? mapStyleForLocalTime(DateTime.now())
        : host.mapStyle;

    if (enabled == host.adaptiveMapStyleEnabled && nextStyle == host.mapStyle) {
      return;
    }

    host.updateMap(() {
      host.adaptiveMapStyleEnabled = enabled;
      host.mapStyle = nextStyle;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ccsAdaptiveMapStylePreferenceKey, enabled);
      if (!enabled) {
        await prefs.setString(ccsMapStylePreferenceKey, nextStyle.name);
      }
    } catch (_) {}
  }

  @override
  void refreshAdaptiveMapStyle() {
    if (!host.mounted || !host.adaptiveMapStyleEnabled) {
      return;
    }

    final nextStyle = mapStyleForLocalTime(DateTime.now());
    if (nextStyle != host.mapStyle) {
      host.updateMap(() => host.mapStyle = nextStyle);
    }
  }

  @override
  List<SourceAttribution> get mapAttributions {
    return [
      TextSourceAttribution(
        'CARTO',
        onTap: () => unawaited(
          launchUrl(
            Uri.parse('https://carto.com/basemaps'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
      TextSourceAttribution(
        'OpenStreetMap contributors',
        onTap: () => unawaited(
          launchUrl(
            Uri.parse('https://www.openstreetmap.org/copyright'),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    ];
  }

  @override
  void pauseMapRealtimeSync() {
    host.liveLocationSubscription?.cancel();
    host.liveLocationSubscription = null;
    host.publicLiveLocationSubscription?.cancel();
    host.publicLiveLocationSubscription = null;
    host.ownLiveLocationSubscription?.cancel();
    host.ownLiveLocationSubscription = null;
    host.policeReportSubscription?.cancel();
    host.policeReportSubscription = null;
    host.sosReportSubscription?.cancel();
    host.sosReportSubscription = null;
  }

  @override
  void resumeMapRealtimeSync() {
    if (!host.mounted || !host.isVisible) {
      return;
    }

    host.presence.startLiveLocationSync();
    unawaited(host.presence.loadFriendLiveLocationUids());
    host.police.startPoliceReportSync();
    host.sos.startSosReportSync();
  }

  @override
  void refreshMap() {
    if (host.defaultMapUsesSpots &&
        !host.mapCameraChangedByUser &&
        mapFocusRequest.value == null) {
      host.navigation.moveMapCamera(loadedSpotsMapCenter(), 3);
    }
    if (!host.mounted) {
      return;
    }

    host.updateMap(() {
      final spot = host.selectedSpot;
      final policeReport = host.selectedPoliceReport;
      final sosReport = host.selectedSosReport;
      final liveLocation = host.selectedLiveLocation;

      if (!host.routePreviewMode &&
          spot != null &&
          (!spot.isVisibleOnMapNow ||
              !spotMatchesSelectedCountries(spot) ||
              !spot.categories.any(spotCategoryFilters.value.contains))) {
        host.selectedSpot = null;
      }

      if (policeReport != null && !policeReport.isActive) {
        host.selectedPoliceReport = null;
      }

      if (sosReport != null && !sosReport.isActive) {
        host.selectedSosReport = null;
      }

      if (liveLocation != null &&
          !host.presence.liveLocationShouldStayVisibleOnMap(liveLocation)) {
        host.selectedLiveLocation = null;
      }
    });
  }

  @override
  Future<void> showMapCategoryFilterSheet() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final nextEnabledCategories = Set<String>.from(spotCategoryFilters.value);
    final availableCountries = availableSpotCountries();
    final nextEnabledCountries = cleanSpotCountries(spotCountryFilters.value);
    if (nextEnabledCountries.isEmpty && availableCountries.isNotEmpty) {
      final ownCountry = cleanSpotCountries(<String>{currentUser.country});
      nextEnabledCountries.add(
        ownCountry.isNotEmpty ? ownCountry.first : availableCountries.first,
      );
    }

    await showModalBottomSheet<void>(
      context: viewContext,
      backgroundColor: panelGlass,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedCount = nextEnabledCategories.length;
            final selectedCountryCount = nextEnabledCountries.length;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: CcsText(
                            'Map filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      localizedSpotFilterSummary(
                        selectedCategories: selectedCount,
                        totalCategories: spotCategoryOptions.length,
                        selectedCountries: selectedCountryCount,
                      ),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 14),
                    spotFilterColumns(
                      context: context,
                      enabledCategories: nextEnabledCategories,
                      enabledCountries: nextEnabledCountries,
                      countries: availableCountries,
                      onChanged: () => setSheetState(() {}),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          updateSpotCategoryFilters(nextEnabledCategories);
                          unawaited(
                            updateSpotCountryFilters(nextEnabledCountries),
                          );
                          host.updateMap(() {
                            host.selectedSpot = null;
                            host.selectedLiveLocation = null;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.tune),
                        label: const CcsText(
                          'Apply filters',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Future<void> showAddMapReportSheet() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final selected = await showModalBottomSheet<String>(
      context: viewContext,
      backgroundColor: panelGlass,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CcsText(
                  'Add map alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: AnimatedBuilder(
                    animation: host.mapAlertPulseController,
                    builder: (context, child) {
                      final pulse = Curves.easeInOut.transform(
                        host.mapAlertPulseController.value,
                      );
                      final color = policeAlertColor(pulse);
                      return Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.72),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.32),
                              blurRadius: 9,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(Icons.local_police, color: color),
                      );
                    },
                  ),
                  title: const CcsText(
                    'Police',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const CcsText(
                    'Mark police at your current location for 2 hours.',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'police'),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: AnimatedBuilder(
                    animation: host.mapAlertPulseController,
                    builder: (context, child) {
                      final pulse = Curves.easeInOut.transform(
                        host.mapAlertPulseController.value,
                      );
                      return Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sosAlertColor.withValues(
                            alpha: 0.18 + pulse * 0.12,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sosAlertColor.withValues(
                              alpha: 0.82 + pulse * 0.18,
                            ),
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: sosAlertColor.withValues(
                                alpha: 0.34 + pulse * 0.22,
                              ),
                              blurRadius: 9 + pulse * 5,
                              spreadRadius: 1 + pulse * 1.5,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: CcsText(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  title: const CcsText(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: const CcsText(
                    'Ask nearby drivers for help.',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: () => Navigator.pop(context, 'sos'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == 'police') {
      await host.police.addPoliceReportAtCurrentLocation();
    } else if (selected == 'sos') {
      await host.sos.addSosReportAtCurrentLocation();
    }
  }

  @override
  void openSpotDetails(CarSpot spot) {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    Navigator.push(
      viewContext,
      appPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
    );
  }
}
