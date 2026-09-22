import '../controllers/map_session.dart';
import '../controllers/map_appearance_controller.dart';
import '../controllers/map_layers_controller.dart';
import '../controllers/map_navigation_controller.dart';
import '../controllers/map_police_controller.dart';
import '../controllers/map_presence_controller.dart';
import '../controllers/map_sharing_controller.dart';
import '../controllers/map_sos_controller.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    show openUserProfile;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show LanguageReactiveState;
import 'package:ccs_app/core/location/coordinates.dart'
    show isValidLatLng, normalizedRotationDegrees;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show setScreenAwakeForMap;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show mapFocusRequest;
import 'package:ccs_app/features/map/widgets/exclusive_map_gestures.dart'
    show ExclusiveMapGestures;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/models/map_style.dart'
    show CcsMapStyle, CcsMapStylePresentation;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/features/map/models/sos_report.dart' show SosReportData;
import 'package:ccs_app/features/map/data/map_overview.dart'
    show loadedSpotsMapCenter;
import 'package:ccs_app/features/map/widgets/map_controls.dart'
    show MapHeader, MapStyleSelector, SpotRouteDistanceBadge;
import 'package:ccs_app/features/map/widgets/report_map_cards.dart'
    show PoliceReportMapCard, SosReportMapCard;
import 'package:ccs_app/features/map/widgets/map_spot_card.dart'
    show LiveLocationMapCard, SpotMapCard;
import 'package:ccs_app/features/map/widgets/map_tile.dart'
    show CcsSmoothMapTileLayer;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show checkGpsSpotVisits, visitDwellProgress;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show availableSpotCountries, spotCategoryFilters, spotCountryFilters;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions;

class MapScreen extends StatefulWidget {
  final bool isVisible;

  const MapScreen({super.key, required this.isVisible});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, LanguageReactiveState
    implements MapSession {
  @override
  bool get isVisible => widget.isVisible;

  @override
  void updateMap(VoidCallback update) => setState(update);

  @override
  late final MapAppearanceActions appearance = MapAppearanceController(this);

  @override
  late final MapLayersActions layers = MapLayersController(this);

  @override
  late final MapNavigationActions navigation = MapNavigationController(this);

  @override
  late final MapPoliceActions police = MapPoliceController(this);

  @override
  late final MapPresenceActions presence = MapPresenceController(this);

  @override
  late final MapSharingActions sharing = MapSharingController(this);

  @override
  late final MapSosActions sos = MapSosController(this);

  // Start from granted GPS permission; otherwise keep the overview of spots.

  // Third map-visual state:
  // icons -> dots -> soft density/fog clouds at regional zoom.

  @override
  double navigationZoom = 10.0;

  // Navigation heading tuning: behave like Waze/Google Maps.
  // While the car is moving we trust the GPS movement vector, not the phone
  // compass, because the compass often points sideways/backwards in a car.
  // walking or driving

  @override
  final mapController = MapController();
  @override
  late final AnimationController mapAlertPulseController;
  @override
  Timer? visitDwellTimer;
  @override
  bool visitDwellPolling = false;
  @override
  Timer? temporarySpotRefreshTimer;
  @override
  Timer? nextTemporarySpotExpiryTimer;
  @override
  Timer? adaptiveMapStyleTimer;
  @override
  Timer? liveLocationUploadTimer;
  @override
  Timer? liveLocationPromptTimer;
  @override
  Timer? liveLocationAutoStopTimer;
  @override
  Timer? liveLocationStaleSweepTimer;
  @override
  Timer? mapGestureIdleTimer;
  @override
  Timer? automaticGpsRetryTimer;
  @override
  DateTime? lastMapCameraUiUpdateAt;
  @override
  late final AnimationController navigationMotionController;
  @override
  DateTime? lastNavigationFrameAt;
  @override
  double displayedNavigationHeading = 0;
  @override
  bool northResetScheduled = false;
  @override
  final followExitGesture = FollowExitGesture();
  @override
  StreamSubscription<Position>? navigationPositionSubscription;
  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  liveLocationSubscription;
  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  publicLiveLocationSubscription;
  @override
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  ownLiveLocationSubscription;
  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  policeReportSubscription;
  @override
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  sosReportSubscription;
  @override
  Timer? sosDistanceCheckTimer;
  @override
  CarSpot? selectedSpot;
  @override
  CarSpot? focusedReviewSpot;
  @override
  CarSpot? routePreviewSpot;
  @override
  bool routePreviewMode = false;
  @override
  bool routePreviewLocating = false;
  @override
  PoliceReportData? selectedPoliceReport;
  @override
  SosReportData? selectedSosReport;
  @override
  LiveLocationData? selectedLiveLocation;
  @override
  LatLng? currentUserLocation;
  @override
  LatLng? displayedUserLocation;
  @override
  LatLng? lastGpsUserLocation;
  @override
  LatLng? lastUploadedLiveLocation;
  @override
  DateTime? lastGpsUserLocationAt;
  @override
  double currentUserSpeedMetersPerSecond = 0;
  @override
  bool isLocatingUser = false;
  @override
  bool isAddingPoliceReport = false;
  @override
  bool isAddingSosReport = false;
  @override
  bool sosConfirmationDialogOpen = false;
  @override
  bool isVotingPoliceReport = false;
  @override
  bool isSharingLiveLocation = false;

  @override
  bool isTogglingLiveLocation = false;
  @override
  bool liveLocationPromptOpen = false;
  @override
  DateTime? liveLocationPromptAt;
  @override
  DateTime? liveLocationExpiresAt;
  @override
  Duration liveLocationShareDuration = const Duration(hours: 1);
  @override
  List<LiveLocationData> liveLocations = [];
  @override
  final Map<String, LiveLocationData> visibleLiveLocationsByUid = {};
  @override
  final Map<String, LiveLocationData> publicLiveLocationsByUid = {};
  @override
  Set<String> friendLiveLocationUids = {};
  @override
  String? nativeLiveLocationBackgroundSignature;
  @override
  List<PoliceReportData> policeReports = [];
  @override
  List<SosReportData> sosReports = [];
  @override
  bool defaultMapUsesSpots = true;
  @override
  LatLng currentMapCenter = loadedSpotsMapCenter();
  @override
  double currentMapZoom = 3;
  @override
  double currentMapRotationDegrees = 0;
  @override
  double currentUserHeadingDegrees = 0;
  @override
  LatLng? previousAcceptedHeadingLocation;
  @override
  double smoothedUserHeadingDegrees = 0;
  @override
  DateTime? lastNavigationPositionAt;
  @override
  bool mapCenteredOnCurrentUser = false;
  @override
  bool mapCameraReady = false;
  @override
  bool initialProfileCityFocusApplied = false;
  @override
  bool initialProfileCityFocusInProgress = false;
  @override
  bool mapCameraChangedByUser = false;
  @override
  int? lastHandledMapFocusRequestToken;
  @override
  CcsMapStyle mapStyle = CcsMapStyle.dark;
  @override
  bool adaptiveMapStyleEnabled = false;
  @override
  bool mapGestureInProgress = false;

  @override
  void initState() {
    super.initState();
    unawaited(setScreenAwakeForMap(widget.isVisible));
    mapAlertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    navigationMotionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(navigation.updatePredictedUserMarker);
    visitDwellTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!widget.isVisible ||
          visitDwellPolling ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
        return;
      visitDwellPolling = true;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse)
          return;
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
        if (mounted && widget.isVisible) await checkGpsSpotVisits(position);
      } catch (_) {
        visitDwellProgress.value = null;
      } finally {
        visitDwellPolling = false;
      }
    });
    reviewSpots.addListener(appearance.refreshMap);
    spotCategoryFilters.addListener(appearance.refreshMap);
    spotCountryFilters.addListener(appearance.refreshMap);
    mapFocusRequest.addListener(navigation.handleMapFocusRequest);

    // Events can become visible or expire just because time passes.
    // Firestore will not send a new snapshot at the start/end time, so the map
    // needs a small live refresh while this screen is open.
    temporarySpotRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => appearance.refreshMap(),
    );
    if (widget.isVisible) {
      appearance.resumeMapRealtimeSync();
    }
    unawaited(appearance.loadMapStylePreference());
    adaptiveMapStyleTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => appearance.refreshAdaptiveMapStyle(),
    );
    sosDistanceCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => sos.checkOwnSosDistance(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) {
        return;
      }

      mapCameraReady = true;
      navigation.restoreMapCamera();
      navigation.handleMapFocusRequest();
      unawaited(navigation.focusInitialMapOnCurrentLocation());
    });
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isVisible == widget.isVisible) {
      return;
    }

    unawaited(setScreenAwakeForMap(widget.isVisible));

    if (!widget.isVisible) {
      mapCameraReady = false;
      automaticGpsRetryTimer?.cancel();
      automaticGpsRetryTimer = null;
      navigationMotionController.stop();
      lastNavigationFrameAt = null;
      if (!isSharingLiveLocation) {
        navigationPositionSubscription?.cancel();
        navigationPositionSubscription = null;
      }
      appearance.pauseMapRealtimeSync();
      return;
    }

    appearance.resumeMapRealtimeSync();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) {
        return;
      }

      mapCameraReady = true;
      navigation.restoreMapCamera();
      navigation.handleMapFocusRequest();
      unawaited(navigation.focusInitialMapOnCurrentLocation());
    });
  }

  @override
  void dispose() {
    unawaited(setScreenAwakeForMap(false));
    visitDwellTimer?.cancel();
    temporarySpotRefreshTimer?.cancel();
    adaptiveMapStyleTimer?.cancel();
    liveLocationUploadTimer?.cancel();
    liveLocationPromptTimer?.cancel();
    liveLocationAutoStopTimer?.cancel();
    liveLocationStaleSweepTimer?.cancel();
    mapGestureIdleTimer?.cancel();
    liveLocationSubscription?.cancel();
    publicLiveLocationSubscription?.cancel();
    ownLiveLocationSubscription?.cancel();
    policeReportSubscription?.cancel();
    sosReportSubscription?.cancel();
    sosDistanceCheckTimer?.cancel();
    navigationPositionSubscription?.cancel();
    automaticGpsRetryTimer?.cancel();
    navigationMotionController.dispose();
    reviewSpots.removeListener(appearance.refreshMap);
    spotCategoryFilters.removeListener(appearance.refreshMap);
    spotCountryFilters.removeListener(appearance.refreshMap);
    mapFocusRequest.removeListener(navigation.handleMapFocusRequest);
    mapAlertPulseController.dispose();
    mapController.dispose();
    super.dispose();
  }

  void finishMapPointer(int pointer) {
    followExitGesture.pointerUp(pointer);
    scheduleNorthReset();
  }

  void scheduleNorthReset() {
    if (followExitGesture.isActive || !northResetScheduled) return;
    // Wait for the gesture wrapper to release its camera constraint first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || followExitGesture.isActive || !northResetScheduled)
        return;
      navigation.resetNorthAfterFocusExit();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spot = selectedSpot;
    final policeReport = selectedPoliceReport;
    final sosReport = selectedSosReport;
    final liveLocation = selectedLiveLocation;
    final hasBottomCard =
        spot != null ||
        policeReport != null ||
        sosReport != null ||
        liveLocation != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          ExclusiveMapGestures(
            mapController: mapController,
            builder: (interactionOptions, constraint) => FlutterMap(
              mapController: mapController,
              options: MapOptions(
                onMapReady: () {
                  mapCameraReady = true;
                  if (widget.isVisible)
                    unawaited(navigation.focusInitialMapOnCurrentLocation());
                },
                initialCenter: currentMapCenter,
                initialZoom: currentMapZoom,
                initialRotation: currentMapRotationDegrees,
                minZoom: 3,
                maxZoom: 18,
                interactionOptions: interactionOptions,
                cameraConstraint: constraint,
                backgroundColor: mapStyle.backgroundColor,
                onMapEvent: (event) {
                  // A rotation around the exact map centre may not emit a
                  // position change, but it still exits GPS focus.
                  if (event is MapEventRotateStart &&
                      mapCenteredOnCurrentUser) {
                    setState(() {
                      navigation.pauseFollowForMapGesture();
                      mapCameraChangedByUser = true;
                    });
                    scheduleNorthReset();
                  }
                },
                onPointerDown: (event, _) {
                  followExitGesture.pointerDown(
                    event.pointer,
                    following: mapCenteredOnCurrentUser,
                    zoom: currentMapZoom,
                  );
                  // A tap (including on a marker) must not stop course-up
                  // following. Only an actual camera gesture below exits it.
                },
                onPointerUp: (event, _) => finishMapPointer(event.pointer),
                onPointerCancel: (event, _) => finishMapPointer(event.pointer),
                onPositionChanged: (camera, hasGesture) {
                  if (!isValidLatLng(camera.center) || !camera.zoom.isFinite) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        navigation.restoreMapCamera();
                      }
                    });
                    return;
                  }

                  final nextZoom = camera.zoom.clamp(3.0, 18.0).toDouble();
                  final nextRotation = normalizedRotationDegrees(
                    camera.rotation,
                    fallback: currentMapRotationDegrees,
                  );
                  final zoomChanged = (nextZoom - currentMapZoom).abs() >= 0.05;
                  final rotationChanged =
                      (nextRotation - currentMapRotationDegrees).abs() >= 0.5;

                  if (zoomChanged || rotationChanged || hasGesture) {
                    final now = DateTime.now();
                    final allowUiRefresh =
                        lastMapCameraUiUpdateAt == null ||
                        now.difference(lastMapCameraUiUpdateAt!) >=
                            const Duration(milliseconds: 90);

                    currentMapCenter = camera.center;
                    currentMapZoom = nextZoom;
                    currentMapRotationDegrees = nextRotation;
                    if (hasGesture) {
                      navigation.pauseFollowForMapGesture();
                      scheduleNorthReset();
                      mapCameraChangedByUser = true;
                      mapGestureIdleTimer?.cancel();
                      mapGestureIdleTimer = Timer(
                        const Duration(milliseconds: 320),
                        () {
                          if (!mounted || !mapGestureInProgress) {
                            return;
                          }
                          setState(() => mapGestureInProgress = false);
                        },
                      );
                    }

                    if (allowUiRefresh) {
                      lastMapCameraUiUpdateAt = now;
                      setState(() {
                        if (hasGesture) {
                          mapGestureInProgress = true;
                        }
                      });
                    } else if (hasGesture && !mapGestureInProgress) {
                      setState(() => mapGestureInProgress = true);
                    }
                  }
                },
                onTap: (_, _) => setState(() {
                  navigation.clearRoutePreviewMode();
                  selectedSpot = null;
                  selectedPoliceReport = null;
                  selectedSosReport = null;
                  selectedLiveLocation = null;
                }),
              ),
              children: [
                CcsSmoothMapTileLayer(mapStyle: mapStyle),
                MarkerLayer(markers: layers.spotFogCloudMarkers),
                MarkerLayer(markers: layers.allMapMarkers),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    navigationMotionController,
                    mapAlertPulseController,
                  ]),
                  builder: (context, _) {
                    final marker = layers.currentUserMarker;
                    return MarkerLayer(markers: [if (marker != null) marker]);
                  },
                ),
                RichAttributionWidget(
                  attributions: appearance.mapAttributions,
                  showFlutterMapAttribution: false,
                  popupBackgroundColor: panelGlass,
                ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: MapHeader(
                    isSharingLiveLocation: isSharingLiveLocation,
                    isBusy: isTogglingLiveLocation,
                    onShareChanged: sharing.toggleLiveLocationSharing,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: MapStyleSelector(
                    selectedStyle: mapStyle,
                    adaptiveEnabled: adaptiveMapStyleEnabled,
                    onSelected: appearance.setMapStyle,
                    onAdaptiveChanged: appearance.setAdaptiveMapStyle,
                    filterEnabledCount:
                        spotCategoryFilters.value.length +
                        spotCountryFilters.value.length,
                    filterTotalCount:
                        spotCategoryOptions.length +
                        availableSpotCountries().length,
                    onFilterTap: appearance.showMapCategoryFilterSheet,
                  ),
                ),
                if (routePreviewMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.center,
                      child: SpotRouteDistanceBadge(
                        spotName: routePreviewSpot?.name ?? '',
                        distanceLabel: navigation.routePreviewDistanceLabel(),
                        isLoading: routePreviewLocating,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: hasBottomCard ? 218 : 50,
            child: FloatingActionButton.small(
              heroTag: 'add_map_report',
              onPressed: (isAddingPoliceReport || isAddingSosReport)
                  ? null
                  : appearance.showAddMapReportSheet,
              backgroundColor: panelGlass,
              foregroundColor: Colors.white,
              child: (isAddingPoliceReport || isAddingSosReport)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
            ),
          ),
          Positioned(
            right: 16,
            bottom: hasBottomCard ? 218 : 50,
            child: FloatingActionButton.small(
              heroTag: 'current_location',
              onPressed: isLocatingUser
                  ? null
                  : () => navigation.moveToCurrentLocation(),
              backgroundColor: blue,
              foregroundColor: Colors.white,
              child: isLocatingUser
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          if (policeReport != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: PoliceReportMapCard(
                report: policeReport,
                isBusy: isVotingPoliceReport,
                canVote: police.canVotePoliceReportFromCurrentMapLocation(
                  policeReport,
                ),
                voteHint: police.policeReportVoteHint(policeReport),
                onStillThere: () =>
                    police.votePoliceReport(policeReport, stillThere: true),
                onNotThere: () =>
                    police.votePoliceReport(policeReport, stillThere: false),
                onDelete:
                    policeReport.uid == FirebaseAuth.instance.currentUser?.uid
                    ? () => police.removePoliceReport(policeReport)
                    : null,
              ),
            ),
          if (sosReport != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SosReportMapCard(
                report: sosReport,
                isOwnReport:
                    sosReport.uid == FirebaseAuth.instance.currentUser?.uid,
                onOpenProfile: () => openUserProfile(
                  context,
                  uid: sosReport.uid,
                  fallbackUsername: sosReport.username,
                ),
                onMessage: () => sos.openSosMessage(sosReport),
                onRoute: () =>
                    navigation.openWazeRouteToLatLng(sosReport.coordinates),
                onDelete:
                    sosReport.uid == FirebaseAuth.instance.currentUser?.uid
                    ? () => sos.removeSosReport(sosReport)
                    : null,
              ),
            ),
          if (spot != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SpotMapCard(
                spot: spot,
                peopleCount: presence.peopleAtSpot(spot).length,
                onPeople: () => presence.showSpotPeople(spot),
                onOpen: () => appearance.openSpotDetails(spot),
              ),
            ),
          if (liveLocation != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: LiveLocationMapCard(
                location: liveLocation,
                isFriend: presence.liveLocationIsFriend(liveLocation),
                onOpen: () => openUserProfile(
                  context,
                  uid: liveLocation.uid,
                  fallbackUsername: liveLocation.username,
                ),
                onRoute: () =>
                    navigation.openWazeRouteToLatLng(liveLocation.coordinates),
              ),
            ),
        ],
      ),
    );
  }
}
