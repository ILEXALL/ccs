import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:ccs_app/core/location/startup_location.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show
        bearingBetweenLatLngDegrees,
        distanceBetweenLatLngMeters,
        isValidLatLng,
        lerpLatLng,
        normalizedHeadingDegrees,
        normalizedRotationDegrees,
        projectLatLngMeters,
        safeLatLngFromPosition,
        usableLiveFix;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show mapFocusRequest;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show userLocationLookupTimeout;
import 'package:ccs_app/features/progression/data/visit_tracking.dart'
    show checkGpsCountryAchievement, checkGpsSpotVisits;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'map_session.dart';
import 'map_config.dart';
import 'navigation_motion.dart';

/// Coordinates navigation behavior using screen-owned state and lifecycle.
class MapNavigationController implements MapNavigationActions {
  final MapSession host;
  final NavigationMotion _motion = NavigationMotion();
  String? _fittedPreview;
  final DateTime Function() _now;
  final void Function(LatLng, double, double)? onCamera;
  final void Function(LatLng, LatLng)? onFit;
  MapNavigationController(
    this.host, {
    DateTime Function()? now,
    this.onCamera,
    this.onFit,
  }) : _now = now ?? DateTime.now;

  @override
  void pauseFollowForMapGesture() {
    if (host.mapCenteredOnCurrentUser) {
      host.navigationZoom = host.currentMapZoom;
    }
    host.mapCenteredOnCurrentUser = false;
    host.northResetScheduled = false;
  }

  @override
  void resetNorthAfterFocusExit() {
    // Manual browsing retains the user's orientation until Follow is tapped.
    host.northResetScheduled = false;
  }

  @override
  void scheduleAutomaticGpsRetry() {
    if (!host.mounted || !host.isVisible || host.automaticGpsRetryTimer != null)
      return;
    host.automaticGpsRetryTimer = Timer(const Duration(seconds: 3), () {
      host.automaticGpsRetryTimer = null;
      if (host.mounted && host.isVisible)
        unawaited(focusInitialMapOnCurrentLocation());
    });
  }

  @override
  Future<void> focusInitialMapOnCurrentLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.initialProfileCityFocusInProgress ||
        !(host.mounted && viewContext.mounted) ||
        !host.isVisible)
      return;
    host.initialProfileCityFocusInProgress = true;
    try {
      final granted = await mapLocationPermissionReady(
        check: Geolocator.checkPermission,
        finishFirstLaunchPrompt: initializeStartupLocation,
      );
      if (!(host.mounted && viewContext.mounted) || !host.isVisible || !granted)
        return;
      if (!await Geolocator.isLocationServiceEnabled()) {
        scheduleAutomaticGpsRetry();
        return;
      }
      if (!(host.mounted && viewContext.mounted) || !host.isVisible) return;
      startNavigationTracking();
      // Use a completed fresh warm-up, never await a startup request that may
      // have stalled while another OS permission dialog was open.
      final warmPosition = warmedStartupPosition;
      if (warmPosition != null && usableLiveFix(warmPosition)) {
        handleNavigationPosition(warmPosition);
      }
      final position = await getMapUserPosition(
        showErrors: false,
        requestPermission: false,
      );
      if (!(host.mounted && viewContext.mounted) || !host.isVisible) return;
      if (position != null) {
        handleNavigationPosition(position);
      } else if (host.currentUserLocation == null ||
          host.navigationPositionSubscription == null) {
        scheduleAutomaticGpsRetry();
      }
    } catch (error) {
      debugPrint('Automatic map GPS could not start: $error');
      scheduleAutomaticGpsRetry();
    } finally {
      host.initialProfileCityFocusInProgress = false;
    }
  }

  @override
  void moveMapCamera(LatLng location, double zoom, {double? rotationDegrees}) {
    if (!isValidLatLng(location) || !zoom.isFinite) {
      return;
    }

    final safeZoom = zoom.clamp(3.0, 18.0).toDouble();
    final safeRotation = normalizedRotationDegrees(
      rotationDegrees ?? host.currentMapRotationDegrees,
    );

    if (zoom > 3) host.defaultMapUsesSpots = false;
    host.currentMapCenter = location;
    host.currentMapZoom = safeZoom;
    host.currentMapRotationDegrees = safeRotation;

    if (!host.isVisible || !host.mapCameraReady) {
      return;
    }

    if (onCamera != null) {
      onCamera!(location, safeZoom, safeRotation);
      return;
    }
    host.mapController.moveAndRotate(location, safeZoom, safeRotation);
  }

  @override
  void restoreMapCamera() {
    if (!host.initialProfileCityFocusApplied &&
        !host.mapCameraChangedByUser &&
        !host.routePreviewMode) {
      final size = MediaQuery.sizeOf(host.context);
      host.currentMapZoom = regionalOverviewZoom(
        size.width,
        math.max(1, size.height - 150),
        host.currentMapCenter.latitude,
      );
      host.initialProfileCityFocusApplied = true;
    }
    moveMapCamera(
      isValidLatLng(host.currentMapCenter)
          ? host.currentMapCenter
          : mapRigaCenter,
      host.currentMapZoom.isFinite ? host.currentMapZoom : mapRigaZoom,
      rotationDegrees: host.currentMapRotationDegrees,
    );
  }

  @override
  LatLng? get routePreviewUserLocation =>
      host.displayedUserLocation ?? host.currentUserLocation;

  @override
  double? get routePreviewDistanceMeters {
    final spot = host.routePreviewSpot;
    final userLocation = routePreviewUserLocation;
    if (!host.routePreviewMode || spot == null || userLocation == null) {
      return null;
    }

    final distance = distanceBetweenLatLngMeters(
      userLocation,
      spot.coordinates,
    );
    return distance.isFinite ? distance : null;
  }

  @override
  String routePreviewDistanceLabel() {
    final distance = routePreviewDistanceMeters;
    if (distance == null) {
      return host.routePreviewLocating
          ? trText('Checking distance...')
          : trText('Distance unavailable');
    }

    return '${(distance / 1000).toStringAsFixed(2)} km';
  }

  @override
  void fitRoutePreviewCamera() {
    final spot = host.routePreviewSpot;
    if (spot == null || !isValidLatLng(spot.coordinates)) {
      return;
    }

    final userLocation = routePreviewUserLocation;
    if (!host.isVisible || !host.mapCameraReady) {
      return;
    }
    final fitKey = '${spot.id}:${userLocation != null}';
    if (_fittedPreview == fitKey) return;
    _fittedPreview = fitKey;

    if (userLocation == null || !isValidLatLng(userLocation)) {
      moveMapCamera(
        spot.coordinates,
        14.8,
        rotationDegrees: host.currentMapRotationDegrees,
      );
      return;
    }

    if (onFit != null) {
      onFit!(spot.coordinates, userLocation);
      return;
    }
    host.mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([spot.coordinates, userLocation]),
        padding: const EdgeInsets.fromLTRB(72, 150, 72, 260),
        minZoom: 4,
        maxZoom: 15.6,
        forceIntegerZoomLevel: false,
      ),
    );
  }

  @override
  void clearRoutePreviewMode() {
    if (!host.routePreviewMode &&
        host.routePreviewSpot == null &&
        !host.routePreviewLocating) {
      return;
    }

    host.routePreviewMode = false;
    host.routePreviewSpot = null;
    host.routePreviewLocating = false;
  }

  @override
  Future<void> startRoutePreviewForSpot(CarSpot spot) async {
    _fittedPreview = null;
    if (!isValidLatLng(spot.coordinates)) {
      return;
    }

    host.updateMap(() {
      host.routePreviewMode = true;
      host.routePreviewSpot = spot;
      host.routePreviewLocating = true;
      host.selectedSpot = spot;
      host.focusedReviewSpot = null;
      host.selectedPoliceReport = null;
      host.selectedSosReport = null;
      host.selectedLiveLocation = null;
      pauseFollowForMapGesture();
    });
    resetNorthAfterFocusExit();
    fitRoutePreviewCamera();

    final position = await getMapUserPosition(showErrors: true);
    if (!host.mounted || host.routePreviewSpot?.id != spot.id) {
      return;
    }

    if (position == null) {
      host.updateMap(() => host.routePreviewLocating = false);
      fitRoutePreviewCamera();
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      host.updateMap(() => host.routePreviewLocating = false);
      fitRoutePreviewCamera();
      return;
    }

    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );

    host.updateMap(() {
      host.currentUserLocation = location;
      host.displayedUserLocation = location;
      host.lastGpsUserLocation = location;
      host.lastGpsUserLocationAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = speed;
      host.routePreviewLocating = false;
    });
    startNavigationTracking();
    _fittedPreview = null;
    fitRoutePreviewCamera();
  }

  @override
  void handleMapFocusRequest() {
    final request = mapFocusRequest.value;

    if (request == null ||
        request.token == host.lastHandledMapFocusRequestToken) {
      return;
    }

    if (!host.isVisible || !host.mapCameraReady) {
      return;
    }

    host.lastHandledMapFocusRequestToken = request.token;
    CarSpot? matchingSpot;
    for (final spot in approvedPublicSpots()) {
      if (spot.id == request.spotId) {
        matchingSpot = spot;
        break;
      }
    }

    final focusSpot = matchingSpot ?? request.spot;

    if (request.routePreview && focusSpot != null) {
      unawaited(startRoutePreviewForSpot(focusSpot));
      return;
    }

    if (host.mounted) {
      host.updateMap(() {
        clearRoutePreviewMode();
        host.selectedSpot = focusSpot;
        host.focusedReviewSpot = matchingSpot == null ? request.spot : null;
        host.selectedPoliceReport = null;
        host.selectedSosReport = null;
        host.selectedLiveLocation = null;
        pauseFollowForMapGesture();
        host.currentMapZoom = 16.4;
      });
    }

    resetNorthAfterFocusExit();
    moveMapCamera(
      request.coordinates,
      16.4,
      rotationDegrees: host.currentMapRotationDegrees,
    );
  }

  @override
  Future<void> openWazeRouteToLatLng(LatLng location) async {
    final wazeAppUrl = Uri.parse(
      'waze://?ll=${location.latitude},${location.longitude}&navigate=yes',
    );
    final wazeWebUrl = Uri.parse(
      'https://waze.com/ul?ll=${location.latitude},${location.longitude}&navigate=yes',
    );

    if (await canLaunchUrl(wazeAppUrl)) {
      await launchUrl(wazeAppUrl, mode: LaunchMode.externalApplication);
      return;
    }

    await launchUrl(wazeWebUrl, mode: LaunchMode.externalApplication);
  }

  @override
  void loadInitialUserLocation() {
    // Auto-enable local GPS only if permission was already granted.
    unawaited(focusInitialMapOnCurrentLocation());
  }

  @override
  void startNavigationTracking() {
    host.navigationPositionSubscription ??=
        Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                  intervalDuration: const Duration(seconds: 1),
                  forceLocationManager: false,
                )
              : AppleSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 0,
                  activityType: ActivityType.automotiveNavigation,
                  pauseLocationUpdatesAutomatically: false,
                ),
        ).listen(
          handleNavigationPosition,
          onError: (Object error) {
            debugPrint('Map GPS stream failed: $error');
            host.navigationPositionSubscription?.cancel();
            host.navigationPositionSubscription = null;
            scheduleAutomaticGpsRetry();
          },
          onDone: () {
            host.navigationPositionSubscription = null;
            scheduleAutomaticGpsRetry();
          },
        );

    if (onCamera == null &&
        host.isVisible &&
        !host.navigationMotionController.isAnimating) {
      host.lastNavigationFrameAt = null;
      host.navigationMotionController.repeat();
    }
  }

  @override
  void handleNavigationPosition(Position position) {
    if (position.isMocked) unawaited(checkGpsSpotVisits(position));
    if (!host.mounted || !usableLiveFix(position)) {
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      return;
    }
    final receivedAt = _now();
    _motion.sample(location, receivedAt, position.speed);
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: _motion.speed,
      accuracyMeters: position.accuracy,
    );

    final currentDisplay = host.displayedUserLocation ?? location;
    final distanceToNewGps = distanceBetweenLatLngMeters(
      currentDisplay,
      location,
    );

    final nextDisplay = distanceToNewGps > 80 && _motion.speed >= .8
        ? location
        : currentDisplay;
    host.updateMap(() {
      host.defaultMapUsesSpots = false;
      host.currentUserLocation = location;
      host.displayedUserLocation = nextDisplay;
      host.lastGpsUserLocation = location;
      host.lastGpsUserLocationAt = receivedAt;
      host.lastNavigationPositionAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = _motion.speed;
    });

    if (host.routePreviewMode) {
      fitRoutePreviewCamera();
    } else if (host.mapCenteredOnCurrentUser) {
      updateFollowCamera(nextDisplay, host.displayedNavigationHeading);
    }
  }

  @override
  void updatePredictedUserMarker() {
    if (!host.mounted || !host.isVisible) return;
    final gpsLocation = host.lastGpsUserLocation ?? host.currentUserLocation;
    final gpsTime = host.lastGpsUserLocationAt;
    if (gpsLocation == null || gpsTime == null || !isValidLatLng(gpsLocation))
      return;
    final now = _now();
    final dt = host.lastNavigationFrameAt == null
        ? 1 / 60
        : now.difference(host.lastNavigationFrameAt!).inMicroseconds / 1000000;
    host.lastNavigationFrameAt = now;
    final blend = navigationBlend(dt);
    host.displayedNavigationHeading = interpolateCourse(
      host.displayedNavigationHeading,
      host.currentUserHeadingDegrees,
      blend,
    );
    _motion.sample(gpsLocation, gpsTime, host.currentUserSpeedMetersPerSecond);
    final age = now.difference(gpsTime).inMilliseconds / 1000.0;
    // Browsing stays unfocused until the user explicitly taps GPS again.
    // Brief bounded visual extrapolation only. Uploaded coordinates remain GPS fixes.
    final target = _motion.speed < 0.8
        ? (_motion.stationaryPosition ?? gpsLocation)
        : projectLatLngMeters(
            gpsLocation,
            host.currentUserHeadingDegrees,
            _motion.distanceAhead(age),
          );
    // Globe packets are predicted at 10 Hz; WebView alone interpolates visuals.
    // Avoid a second display-rate Flutter ticker and a second smoothing delay.
    if (onCamera != null) {
      host.displayedUserLocation = target;
      host.displayedNavigationHeading = host.currentUserHeadingDegrees;
      return;
    }
    host.displayedUserLocation = lerpLatLng(
      host.displayedUserLocation ?? gpsLocation,
      target,
      1 - math.exp(-dt.clamp(0.0, 0.1) / .22),
    );
    if (host.mapCenteredOnCurrentUser &&
        !host.routePreviewMode &&
        !host.mapGestureInProgress) {
      updateFollowCamera(
        host.displayedUserLocation!,
        host.displayedNavigationHeading,
      );
    }
  }

  @override
  Future<Position?> getMapUserPosition({
    required bool showErrors,
    bool requestPermission = true,
  }) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (showErrors && (host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Turn on phone location first.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showErrors && (host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Location permission is needed to show you on the map.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: userLocationLookupTimeout,
        ),
      );
      if (position.isMocked) unawaited(checkGpsSpotVisits(position));
      if (!usableLiveFix(position))
        throw StateError(
          'Waiting for an accurate GPS fix. Enable precise location and try outdoors.',
        );
      return position;
    } on TimeoutException {
      if (showErrors && (host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Could not find your location. Try again in a moment.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    } catch (error) {
      if (showErrors && (host.mounted && viewContext.mounted)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Could not use location: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      return null;
    }
  }

  @override
  double headingForNewUserLocation(
    LatLng nextLocation,
    double rawHeading, {
    double speedMetersPerSecond = 0,
    double accuracyMeters = 0,
  }) {
    final fallback = normalizedHeadingDegrees(host.currentUserHeadingDegrees);
    final hasRawHeading = rawHeading.isFinite && rawHeading >= 0;
    final normalizedRawHeading = normalizedHeadingDegrees(
      rawHeading,
      fallback: fallback,
    );

    final previousLocation =
        host.previousAcceptedHeadingLocation ??
        host.currentUserLocation ??
        host.lastGpsUserLocation;

    if (previousLocation == null) {
      host.previousAcceptedHeadingLocation = nextLocation;
      host.smoothedUserHeadingDegrees =
          hasRawHeading && speedMetersPerSecond >= 1.5
          ? normalizedRawHeading
          : fallback;
      return host.smoothedUserHeadingDegrees;
    }

    final movedMeters = distanceBetweenLatLngMeters(
      previousLocation,
      nextLocation,
    );
    final speed = speedMetersPerSecond.isFinite
        ? math.max(0.0, speedMetersPerSecond)
        : 0.0;
    final accuracy = accuracyMeters.isFinite
        ? math.max(0.0, accuracyMeters)
        : 0.0;
    final movementThreshold = math.max(
      mapGpsCourseBaseMovementMeters,
      math.min(8.0, accuracy * 0.35),
    );

    var targetHeading = host.smoothedUserHeadingDegrees;

    // Waze-like behavior:
    // 1) When the car is moving, direction comes from the GPS movement/course.
    // 2) When stopped or crawling, keep the last good heading instead of using
    //    the phone compass. This prevents the arrow from pointing sideways in a
    //    car, on a magnetic mount, or when the phone is in a pocket/cup holder.
    if (speed >= math.max(1.5, mapGpsCourseMinSpeedMetersPerSecond) &&
        accuracy <= 35 &&
        movedMeters >= movementThreshold &&
        hasRawHeading) {
      targetHeading = normalizedRawHeading;
      host.previousAcceptedHeadingLocation = nextLocation;
    } else if (speed >= math.max(1.5, mapGpsCourseMinSpeedMetersPerSecond) &&
        accuracy <= 35 &&
        movedMeters >= movementThreshold) {
      targetHeading = bearingBetweenLatLngDegrees(
        previousLocation,
        nextLocation,
      );
      host.previousAcceptedHeadingLocation = nextLocation;
    } else if (speed < 0.8 && movedMeters > 25) {
      // GPS can drift while standing. Move the anchor quietly so the next real
      // driving segment does not calculate a bearing from an old point.
      host.previousAcceptedHeadingLocation = nextLocation;
    } else
      host.previousAcceptedHeadingLocation ??= nextLocation;

    final smoothingAmount = speed >= 11.0
        ? 0.58
        : speed >= 5.0
        ? 0.46
        : speed >= mapGpsCourseMinSpeedMetersPerSecond
        ? 0.32
        : 0.14;

    // The globe applies one time-based, rate-limited turn interpolation.
    // Do not staircase that target with a second per-GPS-fix smoothing pass.
    host.smoothedUserHeadingDegrees = onCamera != null
        ? targetHeading
        : smoothHeadingDegrees(
            host.smoothedUserHeadingDegrees,
            targetHeading,
            smoothingAmount,
          );

    return host.smoothedUserHeadingDegrees;
  }

  @override
  double smoothHeadingDegrees(double from, double to, double amount) {
    final a = normalizedHeadingDegrees(from);
    final b = normalizedHeadingDegrees(to);
    final delta = ((b - a + 540) % 360) - 180;

    return normalizedRotationDegrees(a + delta * amount);
  }

  @override
  void updateFollowCamera(LatLng location, double headingDegrees) {
    if (!host.mapCenteredOnCurrentUser ||
        host.routePreviewMode ||
        !isValidLatLng(location) ||
        !host.navigationZoom.isFinite) {
      return;
    }

    // The arrow stays screen-up in follow mode; rotate the road beneath it
    // using the same interpolated course as the moving GPS marker.
    final course = normalizedHeadingDegrees(
      host.displayedNavigationHeading,
      fallback: headingDegrees,
    );
    final rotation = normalizedRotationDegrees(-course);
    if (!host.isVisible || !host.mapCameraReady) {
      moveMapCamera(location, host.navigationZoom, rotationDegrees: rotation);
      return;
    }

    // Place the car below centre, leaving more of the road ahead visible.
    // Rotate first: flutter_map interprets the move offset in camera space.
    if (onCamera != null) {
      moveMapCamera(location, host.navigationZoom, rotationDegrees: rotation);
      return;
    }
    final controller = host.mapController;
    controller.rotate(rotation);
    controller.move(
      location,
      host.navigationZoom.clamp(3.0, 18.0).toDouble(),
      offset: Offset(0, controller.camera.nonRotatedSize.height * 0.18),
    );
    host.currentMapCenter = controller.camera.center;
    host.currentMapZoom = controller.camera.zoom;
    host.currentMapRotationDegrees = rotation;
  }

  @override
  Future<void> moveToCurrentLocation({bool showErrors = true}) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.isLocatingUser) {
      return;
    }

    host.updateMap(() {
      clearRoutePreviewMode();
      host.isLocatingUser = true;
    });

    final position = await getMapUserPosition(showErrors: showErrors);

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    if (position == null) {
      host.updateMap(() => host.isLocatingUser = false);
      return;
    }

    final location = safeLatLngFromPosition(position);
    if (location == null) {
      host.updateMap(() => host.isLocatingUser = false);
      return;
    }
    unawaited(checkGpsCountryAchievement(viewContext, position));
    unawaited(checkGpsSpotVisits(position));

    final speed = position.speed.isFinite ? math.max(0.0, position.speed) : 0.0;
    final heading = headingForNewUserLocation(
      location,
      position.heading,
      speedMetersPerSecond: speed,
      accuracyMeters: position.accuracy,
    );

    host.updateMap(() {
      host.currentUserLocation = location;
      host.displayedUserLocation = location;
      host.lastGpsUserLocation = location;
      host.lastGpsUserLocationAt = DateTime.now();
      host.currentUserHeadingDegrees = heading;
      host.currentUserSpeedMetersPerSecond = speed;
      host.navigationZoom =
          16.35; // Explicit GPS tap enters street-level following.
      host.currentMapZoom = host.navigationZoom;
      host.displayedNavigationHeading = heading;
      host.currentMapRotationDegrees = normalizedRotationDegrees(-heading);
      host.mapCenteredOnCurrentUser = true;
      host.northResetScheduled = false;
      host.selectedSpot = null;
      host.selectedPoliceReport = null;
      host.selectedSosReport = null;
      host.selectedLiveLocation = null;
      host.isLocatingUser = false;
    });

    startNavigationTracking();
    updateFollowCamera(location, heading);
  }
}
