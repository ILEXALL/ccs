import '../controllers/map_session.dart';
import 'globe_map_screen.dart';
import '../models/globe_spot_style.dart';
import '../controllers/map_appearance_controller.dart';
import '../controllers/map_layers_controller.dart';
import '../controllers/map_navigation_controller.dart';
import '../controllers/map_police_controller.dart';
import '../controllers/map_presence_controller.dart';
import '../controllers/map_sharing_controller.dart';
import '../controllers/map_sos_controller.dart';
import 'dart:async';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
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
import 'package:ccs_app/core/location/coordinates.dart' show isValidLatLng;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show setScreenAwakeForMap;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show mapFocusRequest;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/models/map_style.dart' show CcsMapStyle;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/features/map/models/sos_report.dart' show SosReportData;
import 'package:ccs_app/features/map/data/country_capitals.dart';
import 'package:ccs_app/features/map/widgets/report_map_cards.dart'
    show PoliceReportMapCard, SosReportMapCard;
import 'package:ccs_app/features/map/widgets/map_spot_card.dart'
    show LiveLocationMapCard, SpotMapCard;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show checkGpsSpotVisits, visitDwellProgress;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show spotCategoryFilters, spotCountryFilters;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

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
  late final MapNavigationActions navigation = MapNavigationController(
    this,
    onCamera: (location, zoom, rotation) {
      globeCamera = {
        'revision': ++globeCameraRevision,
        'center': [location.longitude, location.latitude],
        'zoom': zoom,
        'bearing': globeFollowRevision > 0 ? -rotation : 0,
      };
    },
    onFit: (a, b) {
      globeCamera = {
        'revision': ++globeCameraRevision,
        'bounds': [
          [a.longitude, a.latitude],
          [b.longitude, b.latitude],
        ],
      };
    },
  );

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
  LatLng currentMapCenter = capitalForProfileCountry(currentUser.country);
  @override
  double currentMapZoom = 6.5;
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

  int globeCameraRevision = 0;
  Map<String, Object?>? globeCamera;
  int globeFollowRevision = 0;

  Widget buildGlobeMap() => GlobeMapScreen(
    isVisible: widget.isVisible,
    onCameraChanged: (lat, lng, zoom) {
      currentMapCenter = LatLng(lat, lng);
      currentMapZoom = zoom;
    },
    onInteraction: () {
      navigation.pauseFollowForMapGesture();
      mapCameraChangedByUser = true;
    },
    isSharing: isSharingLiveLocation,
    sharingExpiresAt: liveLocationExpiresAt,
    onExtendSharing: () async {
      if (isTogglingLiveLocation) return;
      setState(() => isTogglingLiveLocation = true);
      try {
        await sharing.continueLiveLocationSharing();
      } finally {
        if (mounted) setState(() => isTogglingLiveLocation = false);
      }
    },
    sharingBusy: isTogglingLiveLocation,
    onShareChanged: sharing.toggleLiveLocationSharing,
    onFilter: appearance.showMapCategoryFilterSheet,
    onAddReport: appearance.showAddMapReportSheet,
    onLocate: () async {
      await navigation.moveToCurrentLocation();
      if (mounted && mapCenteredOnCurrentUser) globeFollowRevision++;
    },
    cardBuilder: (cardContext, kind, id) {
      if (kind == 'spot') {
        for (final spot in layers.visibleSpots) {
          if (spot.id == id)
            return SpotMapCard(
              spot: spot,
              peopleCount: presence.peopleAtSpot(spot).length,
              onPeople: () => presence.showSpotPeople(spot),
              onOpen: () => appearance.openSpotDetails(spot),
            );
        }
      } else if (kind == 'live') {
        for (final location in liveLocations) {
          if (location.uid == id &&
              presence.liveLocationShouldStayVisibleOnMap(location))
            return LiveLocationMapCard(
              location: location,
              isFriend: presence.liveLocationIsFriend(location),
              onOpen: () => openUserProfile(
                cardContext,
                uid: location.uid,
                fallbackUsername: location.username,
              ),
              onRoute: () =>
                  navigation.openWazeRouteToLatLng(location.coordinates),
            );
        }
      }
      if (kind == 'police') {
        for (final report in layers.visiblePoliceReports) {
          if (report.id == id)
            return PoliceReportMapCard(
              report: report,
              isBusy: isVotingPoliceReport,
              canVote: police.canVotePoliceReportFromCurrentMapLocation(report),
              voteHint: police.policeReportVoteHint(report),
              onStillThere: () =>
                  police.votePoliceReport(report, stillThere: true),
              onNotThere: () =>
                  police.votePoliceReport(report, stillThere: false),
              onDelete: report.uid == FirebaseAuth.instance.currentUser?.uid
                  ? () => police.removePoliceReport(report)
                  : null,
            );
        }
      } else if (kind == 'sos') {
        for (final report in layers.visibleSosReports) {
          if (report.id == id)
            return SosReportMapCard(
              report: report,
              isOwnReport: report.uid == FirebaseAuth.instance.currentUser?.uid,
              onOpenProfile: () => openUserProfile(
                cardContext,
                uid: report.uid,
                fallbackUsername: report.username,
              ),
              onMessage: () => sos.openSosMessage(report),
              onRoute: () =>
                  navigation.openWazeRouteToLatLng(report.coordinates),
              onDelete: report.uid == FirebaseAuth.instance.currentUser?.uid
                  ? () => sos.removeSosReport(report)
                  : null,
            );
        }
      }
      return null;
    },
    readMotion: () {
      final own = displayedUserLocation ?? currentUserLocation;
      return {
        'position': own != null && isValidLatLng(own)
            ? [own.longitude, own.latitude]
            : null,
        'heading': displayedNavigationHeading.isFinite
            ? displayedNavigationHeading
            : 0,
        'following': mapCenteredOnCurrentUser && globeFollowRevision > 0,
        'followRevision': globeFollowRevision,
        'zoom': navigationZoom,
      };
    },
    readFeatures: () {
      if (!mounted || FirebaseAuth.instance.currentUser == null) {
        return {'type': 'FeatureCollection', 'features': <Object>[]};
      }
      Map<String, Object> point(
        String kind,
        String id,
        String label,
        LatLng p, [
        Map<String, Object> presentation = const {},
      ]) => {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [p.longitude, p.latitude],
        },
        'properties': {'kind': kind, 'id': id, 'label': label, ...presentation},
      };
      final own = displayedUserLocation ?? currentUserLocation;
      return {
        'type': 'FeatureCollection',
        'camera': globeCamera,
        'selection': {
          'token': lastHandledMapFocusRequestToken,
          'id': selectedSpot?.id,
        },
        'features': [
          if (routePreviewMode && routePreviewSpot != null && own != null)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [own.longitude, own.latitude],
                  [
                    routePreviewSpot!.coordinates.longitude,
                    routePreviewSpot!.coordinates.latitude,
                  ],
                ],
              },
              'properties': {'kind': 'route'},
            },
          for (final spot in layers.visibleSpots)
            if (isValidLatLng(spot.coordinates))
              point(
                'spot',
                spot.id,
                spot.name,
                spot.coordinates,
                globeSpotStyle(spot),
              ),
          for (final location in liveLocations)
            if (location.uid != FirebaseAuth.instance.currentUser?.uid &&
                presence.liveLocationShouldStayVisibleOnMap(location) &&
                isValidLatLng(location.coordinates))
              point(
                'live',
                location.uid,
                location.username,
                location.coordinates,
                {
                  'icon': presence.liveLocationCarIconAsset(location),
                  'heading': location.headingDegrees,
                },
              ),
          for (final report in layers.visiblePoliceReports)
            if (isValidLatLng(report.coordinates))
              point('police', report.id, 'Police', report.coordinates),
          for (final report in layers.visibleSosReports)
            if (isValidLatLng(report.coordinates))
              point('sos', report.id, 'SOS', report.coordinates),
          if (own != null && isValidLatLng(own))
            point('self', '', 'You', own, {
              'heading': displayedNavigationHeading.isFinite
                  ? displayedNavigationHeading
                  : 0,
            }),
        ],
      };
    },
  );

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
  Widget build(BuildContext context) => buildGlobeMap();
}
