import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;
import 'package:ccs_app/features/map/models/map_style.dart' show CcsMapStyle;
import 'package:ccs_app/features/map/models/police_report.dart'
    show PoliceReportData;
import 'package:ccs_app/features/map/models/sos_report.dart'
    show SosReportData, SosRequestDraft;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

/// The map screen owns its subscriptions, timers and view state. Controllers
/// operate through this typed contract; no additional listeners are created.
/// Cross-controller actions use interfaces to keep dependencies acyclic.
abstract interface class MapSession {
  BuildContext get context;
  bool get mounted;
  bool get isVisible;
  void updateMap(VoidCallback update);
  double get navigationZoom;
  set navigationZoom(double value);
  MapController get mapController;
  AnimationController get mapAlertPulseController;
  Timer? get visitDwellTimer;
  set visitDwellTimer(Timer? value);
  bool get visitDwellPolling;
  set visitDwellPolling(bool value);
  Timer? get temporarySpotRefreshTimer;
  set temporarySpotRefreshTimer(Timer? value);
  Timer? get nextTemporarySpotExpiryTimer;
  set nextTemporarySpotExpiryTimer(Timer? value);
  Timer? get adaptiveMapStyleTimer;
  set adaptiveMapStyleTimer(Timer? value);
  Timer? get liveLocationUploadTimer;
  set liveLocationUploadTimer(Timer? value);
  Timer? get liveLocationPromptTimer;
  set liveLocationPromptTimer(Timer? value);
  Timer? get liveLocationAutoStopTimer;
  set liveLocationAutoStopTimer(Timer? value);
  Timer? get liveLocationStaleSweepTimer;
  set liveLocationStaleSweepTimer(Timer? value);
  Timer? get mapGestureIdleTimer;
  set mapGestureIdleTimer(Timer? value);
  Timer? get automaticGpsRetryTimer;
  set automaticGpsRetryTimer(Timer? value);
  DateTime? get lastMapCameraUiUpdateAt;
  set lastMapCameraUiUpdateAt(DateTime? value);
  AnimationController get navigationMotionController;
  DateTime? get lastNavigationFrameAt;
  set lastNavigationFrameAt(DateTime? value);
  double get displayedNavigationHeading;
  set displayedNavigationHeading(double value);
  bool get northResetScheduled;
  set northResetScheduled(bool value);
  FollowExitGesture get followExitGesture;
  StreamSubscription<Position>? get navigationPositionSubscription;
  set navigationPositionSubscription(StreamSubscription<Position>? value);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get liveLocationSubscription;
  set liveLocationSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get publicLiveLocationSubscription;
  set publicLiveLocationSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  get ownLiveLocationSubscription;
  set ownLiveLocationSubscription(
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? value,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get policeReportSubscription;
  set policeReportSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  get sosReportSubscription;
  set sosReportSubscription(
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? value,
  );
  Timer? get sosDistanceCheckTimer;
  set sosDistanceCheckTimer(Timer? value);
  CarSpot? get selectedSpot;
  set selectedSpot(CarSpot? value);
  CarSpot? get focusedReviewSpot;
  set focusedReviewSpot(CarSpot? value);
  CarSpot? get routePreviewSpot;
  set routePreviewSpot(CarSpot? value);
  bool get routePreviewMode;
  set routePreviewMode(bool value);
  bool get routePreviewLocating;
  set routePreviewLocating(bool value);
  PoliceReportData? get selectedPoliceReport;
  set selectedPoliceReport(PoliceReportData? value);
  SosReportData? get selectedSosReport;
  set selectedSosReport(SosReportData? value);
  LiveLocationData? get selectedLiveLocation;
  set selectedLiveLocation(LiveLocationData? value);
  LatLng? get currentUserLocation;
  set currentUserLocation(LatLng? value);
  LatLng? get displayedUserLocation;
  set displayedUserLocation(LatLng? value);
  LatLng? get lastGpsUserLocation;
  set lastGpsUserLocation(LatLng? value);
  LatLng? get lastUploadedLiveLocation;
  set lastUploadedLiveLocation(LatLng? value);
  DateTime? get lastGpsUserLocationAt;
  set lastGpsUserLocationAt(DateTime? value);
  double get currentUserSpeedMetersPerSecond;
  set currentUserSpeedMetersPerSecond(double value);
  bool get isLocatingUser;
  set isLocatingUser(bool value);
  bool get isAddingPoliceReport;
  set isAddingPoliceReport(bool value);
  bool get isAddingSosReport;
  set isAddingSosReport(bool value);
  bool get sosConfirmationDialogOpen;
  set sosConfirmationDialogOpen(bool value);
  bool get isVotingPoliceReport;
  set isVotingPoliceReport(bool value);
  bool get isSharingLiveLocation;
  set isSharingLiveLocation(bool value);
  bool get isTogglingLiveLocation;
  set isTogglingLiveLocation(bool value);
  bool get liveLocationPromptOpen;
  set liveLocationPromptOpen(bool value);
  DateTime? get liveLocationPromptAt;
  set liveLocationPromptAt(DateTime? value);
  DateTime? get liveLocationExpiresAt;
  set liveLocationExpiresAt(DateTime? value);
  Duration get liveLocationShareDuration;
  set liveLocationShareDuration(Duration value);
  List<LiveLocationData> get liveLocations;
  set liveLocations(List<LiveLocationData> value);
  Map<String, LiveLocationData> get visibleLiveLocationsByUid;
  Map<String, LiveLocationData> get publicLiveLocationsByUid;
  Set<String> get friendLiveLocationUids;
  set friendLiveLocationUids(Set<String> value);
  String? get nativeLiveLocationBackgroundSignature;
  set nativeLiveLocationBackgroundSignature(String? value);
  List<PoliceReportData> get policeReports;
  set policeReports(List<PoliceReportData> value);
  List<SosReportData> get sosReports;
  set sosReports(List<SosReportData> value);
  bool get defaultMapUsesSpots;
  set defaultMapUsesSpots(bool value);
  LatLng get currentMapCenter;
  set currentMapCenter(LatLng value);
  double get currentMapZoom;
  set currentMapZoom(double value);
  double get currentMapRotationDegrees;
  set currentMapRotationDegrees(double value);
  double get currentUserHeadingDegrees;
  set currentUserHeadingDegrees(double value);
  LatLng? get previousAcceptedHeadingLocation;
  set previousAcceptedHeadingLocation(LatLng? value);
  double get smoothedUserHeadingDegrees;
  set smoothedUserHeadingDegrees(double value);
  DateTime? get lastNavigationPositionAt;
  set lastNavigationPositionAt(DateTime? value);
  bool get mapCenteredOnCurrentUser;
  set mapCenteredOnCurrentUser(bool value);
  bool get mapCameraReady;
  set mapCameraReady(bool value);
  bool get initialProfileCityFocusApplied;
  set initialProfileCityFocusApplied(bool value);
  bool get initialProfileCityFocusInProgress;
  set initialProfileCityFocusInProgress(bool value);
  bool get mapCameraChangedByUser;
  set mapCameraChangedByUser(bool value);
  int? get lastHandledMapFocusRequestToken;
  set lastHandledMapFocusRequestToken(int? value);
  CcsMapStyle get mapStyle;
  set mapStyle(CcsMapStyle value);
  bool get adaptiveMapStyleEnabled;
  set adaptiveMapStyleEnabled(bool value);
  bool get mapGestureInProgress;
  set mapGestureInProgress(bool value);
  MapAppearanceActions get appearance;
  MapLayersActions get layers;
  MapNavigationActions get navigation;
  MapPoliceActions get police;
  MapPresenceActions get presence;
  MapSharingActions get sharing;
  MapSosActions get sos;
}

abstract interface class MapAppearanceActions {
  Future<void> loadMapStylePreference();
  Future<void> setMapStyle(CcsMapStyle value);
  Future<void> setAdaptiveMapStyle(bool enabled);
  void refreshAdaptiveMapStyle();
  List<SourceAttribution> get mapAttributions;
  void pauseMapRealtimeSync();
  void resumeMapRealtimeSync();
  void refreshMap();
  Future<void> showMapCategoryFilterSheet();
  Future<void> showAddMapReportSheet();
  void openSpotDetails(CarSpot spot);
}

abstract interface class MapLayersActions {
  double scaledMapIconValue({
    required double zoom,
    required double minZoom,
    required double maxZoom,
    required double minValue,
    required double maxValue,
  });
  double mapZoomOpacity({
    required double hiddenZoom,
    required double visibleZoom,
  });
  List<CarSpot> get visibleSpots;
  double get spotFogOpacity;
  List<Marker> get spotFogCloudMarkers;
  List<Marker> get markers;
  List<Marker> get focusedReviewSpotMarkers;
  List<Marker> get allMapMarkers;
  List<PoliceReportData> get visiblePoliceReports;
  List<Marker> get policeReportMarkers;
  List<SosReportData> get visibleSosReports;
  List<Marker> get sosReportMarkers;
  List<Marker> get liveLocationMarkers;
  Marker? get currentUserMarker;
}

abstract interface class MapNavigationActions {
  void pauseFollowForMapGesture();
  void scheduleAutomaticGpsRetry();
  Future<void> focusInitialMapOnCurrentLocation();
  void moveMapCamera(LatLng location, double zoom, {double? rotationDegrees});
  void restoreMapCamera();
  LatLng? get routePreviewUserLocation;
  double? get routePreviewDistanceMeters;
  String routePreviewDistanceLabel();
  void fitRoutePreviewCamera();
  void clearRoutePreviewMode();
  Future<void> startRoutePreviewForSpot(CarSpot spot);
  void handleMapFocusRequest();
  Future<void> openWazeRouteToLatLng(LatLng location);
  void loadInitialUserLocation();
  void startNavigationTracking();
  void handleNavigationPosition(Position position);
  void updatePredictedUserMarker();
  Future<Position?> getMapUserPosition({
    required bool showErrors,
    bool requestPermission = true,
  });
  double headingForNewUserLocation(
    LatLng nextLocation,
    double rawHeading, {
    double speedMetersPerSecond = 0,
    double accuracyMeters = 0,
  });
  double smoothHeadingDegrees(double from, double to, double amount);
  void updateFollowCamera(LatLng location, double headingDegrees);
  Future<void> moveToCurrentLocation({bool showErrors = true});
}

abstract interface class MapPoliceActions {
  void startPoliceReportSync();
  double? policeReportDistanceMeters(PoliceReportData report);
  bool isPoliceReportCreatorCooldownOver(PoliceReportData report);
  bool canVotePoliceReportFromCurrentMapLocation(PoliceReportData report);
  String policeReportVoteHint(PoliceReportData report);
  Future<void> addPoliceReportAtCurrentLocation();
  Future<void> removePoliceReport(PoliceReportData report);
  Future<void> votePoliceReport(
    PoliceReportData report, {
    required bool stillThere,
  });
}

abstract interface class MapPresenceActions {
  Future<void> loadFriendLiveLocationUids();
  bool liveLocationIsFriend(LiveLocationData location);
  Map<String, List<String>> get spotPresenceGroups;
  List<LiveLocationData> peopleAtSpot(CarSpot spot);
  void showSpotPeople(CarSpot spot);
  String liveLocationCarIconAsset(LiveLocationData location);
  String liveLocationTooltipMessage(LiveLocationData location);
  bool liveLocationCanBeSeenByCurrentUser(
    LiveLocationData location,
    User? firebaseUser,
  );
  bool liveLocationIsNearAnyApprovedSpot(LiveLocationData location);
  bool liveLocationShouldStayVisibleOnMap(LiveLocationData location);
  void updateLiveLocationCacheFromSnapshot(
    Map<String, LiveLocationData> cache,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  );
  void removeLiveLocationFromCaches(String uid);
  void publishLiveLocationCaches();
  void ensureLiveLocationStaleSweepTimer();
  void startLiveLocationSync();
}

abstract interface class MapSharingActions {
  void ensureNativeLiveLocationBackgroundService(
    User firebaseUser,
    LiveLocationData ownLocation,
  );
  void ensureLiveLocationUploadLoop();
  void cancelLiveLocationTimers({bool keepUploadTimer = false});
  void scheduleLiveLocationTimers();
  Future<void> toggleLiveLocationSharing(bool enabled);
  Future<void> startNativeLiveLocationBackgroundService({
    required String uid,
    required List<String> visibleToUserIds,
    required String shareScope,
    required DateTime promptAt,
    required DateTime expiresAt,
  });
  Future<void> stopNativeLiveLocationBackgroundService();
  Future<void> startLiveLocationSharing();
  Future<void> uploadLatestLiveLocation();
  Future<void> recordNearbySpotVisit(Position position, User user);
  Future<void> writeLiveLocation(
    Position position, {
    required bool renewWindow,
    double? headingDegrees,
    Duration? shareDuration,
    List<String>? visibleToUserIds,
    String? visibleToChatId,
    String? visibleToChatName,
    String? shareScope,
  });
  Future<void> stopLiveLocationSharing();
  Future<void> continueLiveLocationSharing();
  Future<void> showLiveLocationRenewPrompt();
}

abstract interface class MapSosActions {
  void startSosReportSync();
  Future<SosRequestDraft?> showSosDescriptionDialog();
  Future<List<String>> loadSosVisibleUserIds(String fallbackUid);
  Future<void> startSosLiveLocationSharing(Position position);
  Future<void> addSosReportAtCurrentLocation();
  Future<void> removeSosReport(SosReportData report);
  Future<void> checkOwnSosDistance();
  Future<void> openSosMessage(SosReportData report);
}
