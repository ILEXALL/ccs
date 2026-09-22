import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:ccs_app/features/map/widgets/spot_presence_marker.dart';
import 'package:ccs_app/features/map/widgets/visit_dwell_marker.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters, headingRadiansForMap, isValidLatLng;
import 'package:ccs_app/core/theme/app_theme.dart'
    show blue, panelGlass, policeAlertColor, sosAlertColor;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/map/models/map_style.dart'
    show CcsMapStyle, CcsMapStylePresentation;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/features/map/models/sos_report.dart' show SosReportData;
import 'package:ccs_app/features/map/widgets/map_controls.dart'
    show
        CompactSpotMapPoint,
        PulsingTemporarySpotIconGlow,
        SpotFogBucket,
        SpotFogCloud;
import 'package:ccs_app/features/map/widgets/spot_presence_sheet.dart'
    show SpotPresenceCount;
import 'package:ccs_app/features/map/widgets/map_marker_badges.dart'
    show TemporaryMapBadge, VerifiedSpotBadge;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show visitDwellProgress;
import 'package:ccs_app/features/progression/widgets/leaderboard_widgets.dart'
    show creatorSpotsText;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show
        approvedPublicSpots,
        mapVisibleSpots,
        spotCategoryFilters,
        spotCountryFilters,
        spotMatchesSelectedCountries;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/features/spots/models/spot_business_status.dart'
    show spotIsClosedNow;
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart'
    show spotColorForSpot, spotIconAssetPathForSpot;
import 'map_session.dart';
import 'map_config.dart';

/// Coordinates layers behavior using screen-owned state and lifecycle.
class MapLayersController implements MapLayersActions {
  final MapSession host;
  MapLayersController(this.host);

  @override
  double scaledMapIconValue({
    required double zoom,
    required double minZoom,
    required double maxZoom,
    required double minValue,
    required double maxValue,
  }) {
    if (maxZoom <= minZoom) {
      return maxValue;
    }

    final progress = ((zoom - minZoom) / (maxZoom - minZoom))
        .clamp(0.0, 1.0)
        .toDouble();
    final easedProgress = Curves.easeOutCubic.transform(progress);
    return minValue + (maxValue - minValue) * easedProgress;
  }

  @override
  double mapZoomOpacity({
    required double hiddenZoom,
    required double visibleZoom,
  }) {
    final progress =
        ((host.currentMapZoom - hiddenZoom) / (visibleZoom - hiddenZoom))
            .clamp(0.0, 1.0)
            .toDouble();
    // Smoothstep reaches both endpoints gently, without a sudden cutoff.
    return progress * progress * (3 - 2 * progress);
  }

  @override
  List<CarSpot> get visibleSpots {
    final routeSpot = host.routePreviewSpot;
    if (host.routePreviewMode && routeSpot != null) {
      return isValidLatLng(routeSpot.coordinates) ? [routeSpot] : const [];
    }
    return mapVisibleSpots(approvedPublicSpots());
  }

  @override
  double get spotFogOpacity {
    if (host.routePreviewMode || host.currentMapZoom >= mapSpotFogFadeOutZoom) {
      return 0;
    }

    // Full fog while the old dots are almost invisible, then smoothly hand
    // visual responsibility back to the dots as the user zooms in.
    if (host.currentMapZoom <= mapSpotFogFullZoom) {
      return 1;
    }

    final fadeProgress =
        ((host.currentMapZoom - mapSpotFogFullZoom) /
                (mapSpotFogFadeOutZoom - mapSpotFogFullZoom))
            .clamp(0.0, 1.0)
            .toDouble();
    final smooth = fadeProgress * fadeProgress * (3 - 2 * fadeProgress);
    return 1 - smooth;
  }

  @override
  List<Marker> get spotFogCloudMarkers {
    final fogOpacity = spotFogOpacity;
    if (fogOpacity <= 0.001 || host.routePreviewMode) {
      return const <Marker>[];
    }

    final enabledCategoryFilters = spotCategoryFilters.value;
    final enabledCountryFilters = spotCountryFilters.value;
    if (enabledCategoryFilters.isEmpty || enabledCountryFilters.isEmpty) {
      return const <Marker>[];
    }

    final zoomProgress =
        ((host.currentMapZoom - 4.0) / (mapSpotFogFadeOutZoom - 4.0))
            .clamp(0.0, 1.0)
            .toDouble();

    // Coarser cells at far zoom = dramatically fewer widgets.
    // Unlike the first version, categories inside the same geographic cell are
    // blended into one representative cloud instead of stacking many clouds.
    final cellDegrees = 1.05 - (1.05 - 0.16) * zoomProgress;

    final buckets = <String, SpotFogBucket>{};
    for (final spot in approvedPublicSpots()) {
      if (spot.status != SpotStatus.approved ||
          !spotMatchesSelectedCountries(spot) ||
          !spot.categories.any(enabledCategoryFilters.contains) ||
          !spot.isVisibleOnMapNow ||
          !isValidLatLng(spot.coordinates)) {
        continue;
      }

      final latCell = (spot.coordinates.latitude / cellDegrees).floor();
      final lngCell = (spot.coordinates.longitude / cellDegrees).floor();
      final key = '$latCell:$lngCell';

      final closedNow = spotIsClosedNow(spot);
      final color = closedNow && !spot.isTemporaryActiveNow
          ? Colors.grey.shade700
          : spot.isTemporaryActiveNow || spot.isTemporaryUpcomingOnMap
          ? Colors.orangeAccent
          : spotColorForSpot(spot);

      final bucket = buckets.putIfAbsent(key, SpotFogBucket.new);
      bucket.add(spot.coordinates, color);
    }

    // Important visual change: farther zoom = physically smaller clouds on
    // screen instead of giant fixed-size blobs.
    final cloudBaseSize = 42.0 + 44.0 * zoomProgress;

    final entries = buckets.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // During an active pinch/zoom gesture keep only the strongest clouds.
    // Once the gesture stops we can afford a little more regional detail.
    final cloudLimit = host.mapGestureInProgress ? 34 : 72;

    return entries.take(cloudLimit).map((bucket) {
      final densityBoost = (1.0 + math.log(bucket.count + 1) * 0.085).clamp(
        1.0,
        1.24,
      );
      final cloudSize = cloudBaseSize * densityBoost;
      final densityOpacity = (0.30 + math.min(0.22, (bucket.count - 1) * 0.035))
          .toDouble();

      return Marker(
        point: bucket.center,
        width: cloudSize,
        height: cloudSize,
        rotate: false,
        child: IgnorePointer(
          child: Opacity(
            opacity: (fogOpacity * densityOpacity).clamp(0.0, 1.0),
            child: SpotFogCloud(color: bucket.color, density: bucket.count),
          ),
        ),
      );
    }).toList();
  }

  @override
  List<Marker> get markers {
    final presence = host.presence.spotPresenceGroups;
    final showFullIcons = host.currentMapZoom >= mapFullSpotIconMinZoom;
    final compactZoomProgress =
        ((host.currentMapZoom - 3) / (mapFullSpotIconMinZoom - 3))
            .clamp(0.0, 1.0)
            .toDouble();
    final compactMarkerSize =
        4.0 + (13.0 - 4.0) * math.pow(compactZoomProgress, 2.7);
    final fullMarkerSize = scaledMapIconValue(
      zoom: host.currentMapZoom,
      minZoom: mapFullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 46,
      maxValue: 70,
    );
    final fullMarkerWidth = scaledMapIconValue(
      zoom: host.currentMapZoom,
      minZoom: mapFullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 96,
      maxValue: 122,
    );
    final fullMarkerHeight = scaledMapIconValue(
      zoom: host.currentMapZoom,
      minZoom: mapFullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 84,
      maxValue: 112,
    );
    final labelFontSize = scaledMapIconValue(
      zoom: host.currentMapZoom,
      minZoom: mapFullSpotIconMinZoom.toDouble(),
      maxZoom: 16,
      minValue: 8.2,
      maxValue: 10,
    );
    final spotNameLabelOpacity = scaledMapIconValue(
      zoom: host.currentMapZoom,
      minZoom: mapFullSpotIconMinZoom.toDouble() + 1.1,
      maxZoom: mapFullSpotIconMinZoom.toDouble() + 3.0,
      minValue: 0,
      maxValue: 1,
    ).clamp(0.0, 1.0).toDouble();

    return visibleSpots.map((spot) {
      const visibilityOpacity = 1.0;
      final closedNow = spotIsClosedNow(spot);
      final isTemporaryActive = spot.isTemporaryActiveNow;
      final isTemporaryUpcoming = spot.isTemporaryUpcomingOnMap;
      final markerColor = closedNow && !isTemporaryActive
          ? Colors.grey.shade700
          : isTemporaryActive || isTemporaryUpcoming
          ? Colors.orangeAccent
          : spotColorForSpot(spot);
      final baseMarkerSize = showFullIcons ? fullMarkerSize : compactMarkerSize;
      final markerVisualSize = isTemporaryActive || isTemporaryUpcoming
          ? baseMarkerSize * (showFullIcons ? 1.16 : 1.04)
          : baseMarkerSize;
      final compactMarkerPadding = showFullIcons
          ? 0.0
          : spot.isTemporary
          ? math.max(2.4, markerVisualSize * (isTemporaryActive ? 0.54 : 0.38))
          : math.max(1.4, markerVisualSize * 0.26);
      final markerWidth = showFullIcons
          ? fullMarkerWidth + (spot.isTemporary ? 30 : 0)
          : math.max(
              44.0,
              markerVisualSize + (spot.isTemporary ? compactMarkerPadding : 8),
            );
      final markerHeight = showFullIcons
          ? fullMarkerHeight +
                (isTemporaryUpcoming
                    ? 34
                    : isTemporaryActive
                    ? 24
                    : 0)
          : math.max(
              44.0,
              markerVisualSize + (spot.isTemporary ? compactMarkerPadding : 8),
            );
      final markerOpacity = isTemporaryUpcoming || closedNow ? 0.80 : 1.0;
      final iconTopPadding = math.max(
        0.0,
        (markerHeight - markerVisualSize) / 2,
      );
      final mapNameLabelTop = math.max(0.0, iconTopPadding - labelFontSize - 3);
      final mapStartLabelBottom = math.max(0.0, iconTopPadding - 14);

      Widget iconWidget() {
        final asset = spotIconAssetPathForSpot(spot, mapStyle: host.mapStyle);
        final image = Image.asset(
          asset,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return CompactSpotMapPoint(
              color: markerColor,
              faded: isTemporaryUpcoming || closedNow,
              event: isTemporaryActive || isTemporaryUpcoming,
            );
          },
        );

        final rawIcon = SizedBox(
          width: markerVisualSize,
          height: markerVisualSize,
          child: closedNow || isTemporaryUpcoming
              ? Opacity(
                  opacity: markerOpacity,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      markerColor,
                      BlendMode.srcATop,
                    ),
                    child: image,
                  ),
                )
              : image,
        );

        final icon =
            host.mapStyle == CcsMapStyle.light && !host.mapGestureInProgress
            ? SizedBox(
                width: markerVisualSize,
                height: markerVisualSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipOval(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 1.6, sigmaY: 1.6),
                        child: SizedBox(
                          width: markerVisualSize * 0.78,
                          height: markerVisualSize * 0.78,
                        ),
                      ),
                    ),
                    rawIcon,
                  ],
                ),
              )
            : rawIcon;

        Widget withVerifiedBadge(Widget child) {
          if (!spot.verifiedOnly) {
            return child;
          }

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              child,
              Positioned(
                right: -2,
                top: -2,
                child: VerifiedSpotBadge(
                  size: markerVisualSize.clamp(13.0, 18.0).toDouble(),
                ),
              ),
            ],
          );
        }

        if (!isTemporaryActive) {
          return withVerifiedBadge(icon);
        }

        return withVerifiedBadge(
          PulsingTemporarySpotIconGlow(size: markerVisualSize, child: icon),
        );
      }

      Widget fullMarker() {
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: mapNameLabelTop,
              left: 2,
              right: 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: spotNameLabelOpacity,
                  child: CcsText(
                    spot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: closedNow || isTemporaryUpcoming
                          ? host.mapStyle.mapMutedLabelColor
                          : host.mapStyle.mapLabelColor.withValues(alpha: 0.82),
                      fontSize: labelFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      shadows: [
                        Shadow(
                          color: host.mapStyle.mapLabelShadowColor,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            iconWidget(),
            if (isTemporaryActive)
              Positioned(
                right: 2,
                top: iconTopPadding + markerVisualSize * 0.28,
                child: const TemporaryMapBadge(),
              ),
            if (isTemporaryUpcoming)
              Positioned(
                left: 2,
                right: 2,
                bottom: mapStartLabelBottom,
                child: IgnorePointer(
                  child: CcsText(
                    spot.temporaryStartingAtLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
          ],
        );
      }

      Widget compactMarker() {
        final point = CompactSpotMapPoint(
          color: markerColor,
          size: markerVisualSize,
          faded: isTemporaryUpcoming || closedNow,
          event: isTemporaryActive || isTemporaryUpcoming,
        );

        Widget marker = host.mapStyle == CcsMapStyle.light
            ? SizedBox(
                width: markerVisualSize + 12,
                height: markerVisualSize + 12,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: markerVisualSize + 3,
                      height: markerVisualSize + 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.52),
                            blurRadius: 6,
                            spreadRadius: 0.45,
                            offset: const Offset(0, 1.4),
                          ),
                          BoxShadow(
                            color: markerColor.withValues(alpha: 0.18),
                            blurRadius: 4,
                            spreadRadius: 0.15,
                          ),
                        ],
                      ),
                    ),
                    point,
                  ],
                ),
              )
            : point;

        if (isTemporaryActive) {
          marker = PulsingTemporarySpotIconGlow(
            size: markerVisualSize,
            compact: true,
            child: point,
          );
        }

        return marker;
      }

      final peopleCount = presence[spot.id]?.length ?? 0;
      final showPeople = host.currentMapZoom >= 14 && peopleCount > 0;
      return Marker(
        key: ValueKey('spot_${spot.id}'),
        point: spot.coordinates,
        alignment: showFullIcons
            ? spotIconTipAlignment(
                asset: spotIconAssetPathForSpot(spot, mapStyle: host.mapStyle),
                iconSize: markerVisualSize,
                markerWidth:
                    markerWidth +
                    (showPeople ? SpotPresenceMarker.sideSpace * 2 : 0),
                markerHeight: markerHeight,
              )
            : Alignment.center,
        width:
            markerWidth + (showPeople ? SpotPresenceMarker.sideSpace * 2 : 0),
        height: markerHeight,
        rotate: true,
        child: IgnorePointer(
          ignoring: visibilityOpacity <= 0.05,
          child: Opacity(
            opacity: visibilityOpacity,
            child: SpotPresenceMarker(
              onSpotTap: () {
                host.updateMap(() {
                  host.selectedSpot = spot;
                  host.selectedPoliceReport = null;
                  host.selectedSosReport = null;
                  host.selectedLiveLocation = null;
                });
              },
              marker: ValueListenableBuilder<VisitDwellProgress?>(
                valueListenable: visitDwellProgress,
                builder: (context, progress, child) => VisitDwellMarker(
                  progress:
                      progress?.userId ==
                              FirebaseAuth.instance.currentUser?.uid &&
                          progress?.spotId == spot.id
                      ? progress
                      : null,
                  label: creatorSpotsText(
                    'Stay for 5 minutes',
                    'Оставайся 5 минут',
                    'Paliec 5 minūtes',
                  ),
                  child: child!,
                ),
                child: showFullIcons ? fullMarker() : compactMarker(),
              ),
              peopleButton: showPeople
                  ? SpotPresenceCount(
                      count: peopleCount,
                      onTap: () => host.presence.showSpotPeople(spot),
                    )
                  : null,
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  List<Marker> get focusedReviewSpotMarkers {
    final spot = host.focusedReviewSpot;
    if (spot == null || !isValidLatLng(spot.coordinates)) {
      return const <Marker>[];
    }

    final alreadyVisible = markers.any(
      (marker) =>
          distanceBetweenLatLngMeters(marker.point, spot.coordinates) < 1,
    );
    if (alreadyVisible) {
      return const <Marker>[];
    }

    return [
      Marker(
        point: spot.coordinates,
        width: 64,
        height: 64,
        rotate: true,
        child: GestureDetector(
          onTap: () {
            host.updateMap(() {
              host.selectedSpot = spot;
              host.selectedPoliceReport = null;
              host.selectedSosReport = null;
              host.selectedLiveLocation = null;
            });
          },
          child: Tooltip(
            message: 'Submitted pin: ${spot.name}',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  List<Marker> get allMapMarkers {
    if (host.routePreviewMode) {
      final routeMarkers = [...markers];

      return routeMarkers
          .where((marker) => isValidLatLng(marker.point))
          .toList();
    }

    final allMarkers = [
      ...markers,
      ...focusedReviewSpotMarkers,
      ...policeReportMarkers,
      ...sosReportMarkers,
      ...liveLocationMarkers,
    ];

    return allMarkers.where((marker) => isValidLatLng(marker.point)).toList();
  }

  @override
  List<PoliceReportData> get visiblePoliceReports {
    return host.policeReports.where((report) => report.isActive).toList();
  }

  @override
  List<Marker> get policeReportMarkers {
    final zoomOpacity = mapZoomOpacity(hiddenZoom: 5, visibleZoom: 12);
    if (zoomOpacity == 0) {
      return const <Marker>[];
    }
    final showPoliceRadius = host.currentMapZoom >= 14.2;
    final compactZoomProgress = ((host.currentMapZoom - 5) / (14.2 - 5))
        .clamp(0.0, 1.0)
        .toDouble();
    final markerOuterSize = showPoliceRadius
        ? scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 14.2,
            maxZoom: 17,
            minValue: 42,
            maxValue: 74,
          )
        : 3.0 + 19.0 * math.pow(compactZoomProgress, 2.4).toDouble();
    final markerInnerSize = showPoliceRadius ? 34.0 : markerOuterSize * 0.6;
    return visiblePoliceReports.map((report) {
      return Marker(
        key: ValueKey('police_${report.id}'),
        point: report.coordinates,
        width: markerOuterSize,
        height: markerOuterSize,
        child: IgnorePointer(
          ignoring: zoomOpacity <= 0.05,
          child: Opacity(
            opacity: zoomOpacity,
            child: GestureDetector(
              onTap: () {
                host.updateMap(() {
                  host.selectedPoliceReport = report;
                  host.selectedSpot = null;
                  host.selectedSosReport = null;
                  host.selectedLiveLocation = null;
                });
              },
              child: Tooltip(
                message: 'Police marked by ${displayUsername(report.username)}',
                child: AnimatedBuilder(
                  animation: host.mapAlertPulseController,
                  builder: (context, child) {
                    final progress = Curves.easeInOut.transform(
                      host.mapAlertPulseController.value,
                    );
                    final color = policeAlertColor(progress);
                    return Container(
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: showPoliceRadius ? 0.14 : 0.90,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(
                            alpha: showPoliceRadius ? 0.72 : 1,
                          ),
                          width: showPoliceRadius ? 2 : markerOuterSize * 0.07,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.32),
                            blurRadius: showPoliceRadius
                                ? 18
                                : markerOuterSize * 0.4,
                            spreadRadius: showPoliceRadius
                                ? 3
                                : markerOuterSize * 0.04,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: markerInnerSize,
                          height: markerInnerSize,
                          decoration: BoxDecoration(
                            color: showPoliceRadius ? panelGlass : color,
                            shape: BoxShape.circle,
                            border: showPoliceRadius
                                ? Border.all(color: color, width: 2)
                                : null,
                          ),
                          child: showPoliceRadius
                              ? Icon(Icons.local_police, color: color, size: 21)
                              : const SizedBox.shrink(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  List<SosReportData> get visibleSosReports {
    return host.sosReports.where((report) => report.isActive).toList();
  }

  @override
  List<Marker> get sosReportMarkers {
    final showSosRadius = host.currentMapZoom >= 14.2;
    final markerOuterSize = showSosRadius
        ? scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 14.2,
            maxZoom: 17,
            minValue: 46,
            maxValue: 82,
          )
        : scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 4,
            maxZoom: 14.2,
            minValue: 15,
            maxValue: 26,
          );
    final markerInnerSize = showSosRadius
        ? 38.0
        : math.max(10.0, markerOuterSize - 8);
    return visibleSosReports.map((report) {
      return Marker(
        point: report.coordinates,
        width: markerOuterSize,
        height: markerOuterSize,
        child: GestureDetector(
          onTap: () {
            host.updateMap(() {
              host.selectedSosReport = report;
              host.selectedSpot = null;
              host.selectedPoliceReport = null;
              host.selectedLiveLocation = null;
            });
          },
          child: Tooltip(
            message: 'SOS by ${displayUsername(report.username)}',
            child: AnimatedBuilder(
              animation: host.mapAlertPulseController,
              builder: (context, child) {
                final pulse = Curves.easeInOut.transform(
                  host.mapAlertPulseController.value,
                );
                final alpha = showSosRadius
                    ? 0.18 + pulse * 0.12
                    : 0.82 + pulse * 0.14;
                return Container(
                  decoration: BoxDecoration(
                    color: sosAlertColor.withValues(alpha: alpha),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sosAlertColor.withValues(
                        alpha: 0.82 + pulse * 0.18,
                      ),
                      width: showSosRadius ? 2.2 : 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: sosAlertColor.withValues(
                          alpha: 0.34 + pulse * 0.22,
                        ),
                        blurRadius: showSosRadius
                            ? 16 + pulse * 10
                            : 9 + pulse * 5,
                        spreadRadius: showSosRadius
                            ? 2 + pulse * 4
                            : 1 + pulse * 1.5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: markerInnerSize,
                      height: markerInnerSize,
                      decoration: BoxDecoration(
                        color: showSosRadius ? panelGlass : sosAlertColor,
                        shape: BoxShape.circle,
                        border: showSosRadius
                            ? Border.all(color: sosAlertColor, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: CcsText(
                          showSosRadius ? 'SOS' : '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  List<Marker> get liveLocationMarkers {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final grouped = host.currentMapZoom >= 14
        ? host.presence.spotPresenceGroups.values.expand((ids) => ids).toSet()
        : <String>{};

    return host.liveLocations
        .where(host.presence.liveLocationShouldStayVisibleOnMap)
        .where((location) => location.uid != firebaseUser?.uid)
        .where((location) => !grouped.contains(location.uid))
        .map((location) {
          final carIconSize = scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 9,
            maxValue: 34,
          );
          final labelWidth = scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 58,
            maxValue: 82,
          );
          final labelFontSize = scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 4,
            maxZoom: 17,
            minValue: 7.8,
            maxValue: 10.5,
          );
          final userNameLabelOpacity = scaledMapIconValue(
            zoom: host.currentMapZoom,
            minZoom: 10.8,
            maxZoom: 14.2,
            minValue: 0,
            maxValue: 1,
          ).clamp(0.0, 1.0).toDouble();
          final markerHeight = carIconSize + 36;
          final iconAsset = host.presence.liveLocationCarIconAsset(location);
          final fallbackColor = host.presence.liveLocationIsFriend(location)
              ? Colors.purpleAccent
              : location.verified
              ? blue
              : Colors.greenAccent;

          return Marker(
            point: location.coordinates,
            width: labelWidth,
            height: markerHeight,
            rotate: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                host.updateMap(() {
                  host.selectedLiveLocation = location;
                  host.selectedSpot = null;
                  host.selectedPoliceReport = null;
                  host.selectedSosReport = null;
                });
              },
              child: Tooltip(
                message: host.presence.liveLocationTooltipMessage(location),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      left: 2,
                      right: 2,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: userNameLabelOpacity,
                          child: CcsText(
                            displayUsername(location.username),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: host.mapStyle.mapLabelColor.withValues(
                                alpha: 0.82,
                              ),
                              fontSize: labelFontSize,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              shadows: [
                                Shadow(
                                  color: host.mapStyle.mapLabelShadowColor,
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: SizedBox(
                        width: carIconSize,
                        height: carIconSize,
                        child: Transform.rotate(
                          angle: headingRadiansForMap(
                            location.headingDegrees,
                            host.currentMapRotationDegrees,
                          ),
                          child: Image.asset(
                            iconAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.directions_car,
                                color: fallbackColor,
                                size: carIconSize * 0.82,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        })
        .toList();
  }

  @override
  Marker? get currentUserMarker {
    final location = host.displayedUserLocation ?? host.currentUserLocation;
    if (location == null || !isValidLatLng(location)) return null;
    final size = navigationArrowSize(host.currentMapZoom);
    return Marker(
      point: location,
      width: size,
      height: size,
      rotate: false,
      child: Tooltip(
        message: trText('Your location'),
        child: NavigationArrow(
          headingDegrees: host.displayedNavigationHeading,
          pulse: host.mapAlertPulseController.value,
        ),
      ),
    );
  }
}
