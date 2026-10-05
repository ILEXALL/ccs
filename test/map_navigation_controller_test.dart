import 'package:ccs_app/features/map/controllers/map_navigation_controller.dart';
import 'package:ccs_app/features/map/controllers/map_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class NavigationSession extends Fake implements MapSession {
  @override
  bool mapCenteredOnCurrentUser = true;
  @override
  bool routePreviewMode = false;
  @override
  bool northResetScheduled = false;
  @override
  double currentUserHeadingDegrees = 90;
  @override
  double smoothedUserHeadingDegrees = 90;
  @override
  LatLng? previousAcceptedHeadingLocation = const LatLng(56.95, 24.1);
  @override
  LatLng? currentUserLocation;
  @override
  LatLng? lastGpsUserLocation;
  @override
  LatLng currentMapCenter = const LatLng(56.95, 24.1);
  @override
  double currentMapZoom = 11.25;
  @override
  double currentMapRotationDegrees = 40;
  @override
  bool defaultMapUsesSpots = true;
  @override
  bool get isVisible => false;
  @override
  bool get mapCameraReady => false;
  @override
  double displayedNavigationHeading = 0;
  @override
  double navigationZoom = 16.35;
}

class GlobeNavigationSession extends NavigationSession {
  @override
  bool get isVisible => true;
  @override
  bool get mapCameraReady => true;
}

void main() {
  test(
    'globe receives camera movement without an attached raster controller',
    () {
      final session = GlobeNavigationSession();
      final moves = <List<double>>[];
      final navigation = MapNavigationController(
        session,
        onCamera: (p, zoom, rotation) =>
            moves.add([p.latitude, p.longitude, zoom, rotation]),
      );
      navigation.moveMapCamera(const LatLng(57, 24), 16, rotationDegrees: 90);
      expect(moves.single, [57, 24, 16, 90]);
      session.displayedNavigationHeading = 45;
      navigation.updateFollowCamera(const LatLng(58, 25), 45);
      expect(moves.last[0], 58);
      expect(moves.last[3], 315);
    },
  );
  test('heading interpolation crosses north through the shortest turn', () {
    final navigation = MapNavigationController(NavigationSession());
    expect(navigation.smoothHeadingDegrees(350, 10, 0.5), closeTo(0, 0.001));
    expect(navigation.smoothHeadingDegrees(10, 350, 0.5), closeTo(0, 0.001));
    expect(navigation.smoothHeadingDegrees(10, 350, 0.75), closeTo(355, 0.001));
  });

  test('follow camera cancels the displayed course in every direction', () {
    final session = NavigationSession();
    final navigation = MapNavigationController(session);
    for (final course in [0.0, 45.0, 90.0, 180.0, 270.0, 350.0, 359.0, 1.0]) {
      session.displayedNavigationHeading = course;
      navigation.updateFollowCamera(const LatLng(56, 24), course);
      expect(
        (session.currentMapRotationDegrees + course) % 360,
        closeTo(0, 0.001),
      );
      expect(session.currentMapZoom, session.navigationZoom);
    }
  });

  test('stationary GPS noise preserves the last course', () {
    final session = NavigationSession();
    final navigation = MapNavigationController(session);
    final heading = navigation.headingForNewUserLocation(
      const LatLng(56.950001, 24.1),
      270,
      speedMetersPerSecond: 0,
      accuracyMeters: 10,
    );
    expect(heading, 90);
  });

  test('moving GPS course updates the screen-owned heading state', () {
    final session = NavigationSession()
      ..currentUserHeadingDegrees = 0
      ..smoothedUserHeadingDegrees = 0;
    final navigation = MapNavigationController(session);
    const location = LatLng(56.95, 24.101);
    expect(
      navigation.headingForNewUserLocation(
        location,
        90,
        speedMetersPerSecond: 12,
        accuracyMeters: 3,
      ),
      closeTo(52.2, 0.001),
    );
    expect(session.previousAcceptedHeadingLocation, location);
    expect(session.smoothedUserHeadingDegrees, closeTo(52.2, 0.001));
  });

  test(
    'camera rejects invalid input and clamps valid zoom before mounting',
    () {
      final session = NavigationSession();
      final navigation = MapNavigationController(session);
      final originalCenter = session.currentMapCenter;
      navigation.moveMapCamera(const LatLng(56, 24), double.nan);
      navigation.moveMapCamera(LatLng(double.nan, 24), 12);
      expect(session.currentMapCenter, originalCenter);
      expect(session.currentMapZoom, 11.25);
      navigation.moveMapCamera(const LatLng(56, 24), 25, rotationDegrees: 450);
      expect(session.currentMapCenter, const LatLng(56, 24));
      expect(session.currentMapZoom, 18);
      expect(session.currentMapRotationDegrees, 90);
      expect(session.defaultMapUsesSpots, false);
      navigation.moveMapCamera(const LatLng(56, 24), 16, rotationDegrees: -90);
      expect(session.currentMapRotationDegrees, 270);
      navigation.moveMapCamera(const LatLng(56, 24), 0);
      expect(session.currentMapZoom, 3);
    },
  );
}
