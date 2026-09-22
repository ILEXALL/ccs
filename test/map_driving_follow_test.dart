import 'package:ccs_app/core/location/coordinates.dart';
import 'package:ccs_app/features/map/controllers/map_layers_controller.dart';
import 'package:ccs_app/features/map/controllers/map_navigation_controller.dart';
import 'package:ccs_app/features/map/widgets/navigation_arrow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'map_navigation_controller_test.dart' show NavigationSession;

class DrivingSession extends NavigationSession {
  @override
  bool get mounted => true;
  @override
  bool get isVisible => true;
  @override
  bool get mapCameraReady => true;
  @override
  final MapController mapController = MapController();
  @override
  late AnimationController mapAlertPulseController;
  @override
  bool mapCenteredOnCurrentUser = true;
  @override
  bool routePreviewMode = false;
  @override
  bool mapGestureInProgress = false;
  @override
  final FollowExitGesture followExitGesture = FollowExitGesture();
  @override
  LatLng? displayedUserLocation = const LatLng(56.95, 24.1);
  @override
  DateTime? lastGpsUserLocationAt;
  @override
  DateTime? lastNavigationFrameAt;
  @override
  double currentUserSpeedMetersPerSecond = 10;
  @override
  void updateMap(VoidCallback update) => update();
}

void main() {
  testWidgets(
    'driving turns rotate the real camera under a fixed upward arrow',
    (tester) async {
      var now = DateTime(2026, 9, 22, 16);
      final session = DrivingSession()
        ..lastGpsUserLocation = const LatLng(56.95, 24.1)
        ..lastGpsUserLocationAt = now
        ..mapAlertPulseController = AnimationController(vsync: tester);
      final navigation = MapNavigationController(session, now: () => now);
      final layers = MapLayersController(session);
      Widget map() => MaterialApp(
        home: FlutterMap(
          mapController: session.mapController,
          options: const MapOptions(
            initialCenter: LatLng(56.95, 24.1),
            initialZoom: 16.35,
          ),
          children: [
            MarkerLayer(markers: [layers.currentUserMarker!]),
          ],
        ),
      );
      await tester.pumpWidget(map());
      for (final course in [350.0, 10.0, 90.0, 180.0, 270.0]) {
        session.currentUserHeadingDegrees = course;
        for (var frame = 0; frame < 12; frame++) {
          now = now.add(const Duration(milliseconds: 16));
          navigation.updatePredictedUserMarker();
          await tester.pumpWidget(map());
          final camera = session.mapController.camera;
          expect(
            normalizedRotationDegrees(
              camera.rotation + session.displayedNavigationHeading,
            ),
            closeTo(0, 0.001),
          );
          final car = camera.latLngToScreenOffset(
            session.displayedUserLocation!,
          );
          expect(car.dx, closeTo(camera.nonRotatedSize.width * 0.5, 0.01));
          expect(car.dy, closeTo(camera.nonRotatedSize.height * 0.68, 0.01));
          final paint = find.descendant(
            of: find.byType(NavigationArrow),
            matching: find.byType(CustomPaint),
          );
          final box = tester.renderObject<RenderBox>(paint);
          final center = box.localToGlobal(box.size.center(Offset.zero));
          final tip = box.localToGlobal(Offset(box.size.width / 2, 0));
          expect(tip.dx, closeTo(center.dx, 0.01));
          expect(tip.dy, lessThan(center.dy));
        }
      }
      // Browsing restores geographic arrow direction instead of forcing north.
      session.mapCenteredOnCurrentUser = false;
      expect(layers.currentUserMarker!.rotate, isFalse);
      await tester.pumpWidget(const SizedBox());
      session.mapController.dispose();
      session.mapAlertPulseController.dispose();
    },
  );

  testWidgets(
    'exiting focus resets north once and never resumes automatically',
    (tester) async {
      var now = DateTime(2026, 9, 22, 16);
      final session = DrivingSession()
        ..lastGpsUserLocation = const LatLng(56.95, 24.1)
        ..lastGpsUserLocationAt = now;
      final navigation = MapNavigationController(session, now: () => now);
      await tester.pumpWidget(
        MaterialApp(
          home: FlutterMap(
            mapController: session.mapController,
            options: const MapOptions(initialCenter: LatLng(56.95, 24.1)),
            children: const [],
          ),
        ),
      );
      session.currentMapZoom = 15;
      session.mapController.rotate(90);
      session.followExitGesture.pointerDown(1, following: true, zoom: 15);
      navigation.pauseFollowForMapGesture();
      expect(session.mapCenteredOnCurrentUser, isFalse);
      navigation.resetNorthAfterFocusExit();
      expect(
        session.mapController.camera.rotation,
        90,
        reason: 'reset waits for the active gesture to finish',
      );
      session.followExitGesture.pointerUp(1);
      navigation.resetNorthAfterFocusExit();
      expect(session.mapController.camera.rotation, 0);
      expect(session.currentMapRotationDegrees, 0);
      expect(session.northResetScheduled, isFalse);
      now = now.add(const Duration(seconds: 4));
      session.lastGpsUserLocationAt = now;
      navigation.updatePredictedUserMarker();
      expect(session.mapCenteredOnCurrentUser, isFalse);
      now = now.add(const Duration(seconds: 4));
      navigation.updatePredictedUserMarker();
      expect(session.mapCenteredOnCurrentUser, isFalse, reason: 'stale GPS');
      session.lastGpsUserLocationAt = now;
      session.currentUserSpeedMetersPerSecond = 0;
      navigation.updatePredictedUserMarker();
      expect(session.mapCenteredOnCurrentUser, isFalse, reason: 'stopped');
      session.currentUserSpeedMetersPerSecond = 10;
      session.followExitGesture.pointerDown(1, following: false, zoom: 15);
      navigation.updatePredictedUserMarker();
      expect(
        session.mapCenteredOnCurrentUser,
        isFalse,
        reason: 'finger still down',
      );
      session.followExitGesture.pointerUp(1);
      session.routePreviewMode = true;
      navigation.updatePredictedUserMarker();
      expect(
        session.mapCenteredOnCurrentUser,
        isFalse,
        reason: 'route preview',
      );
      session.routePreviewMode = false;
      navigation.updatePredictedUserMarker();
      expect(session.mapCenteredOnCurrentUser, isFalse);
      expect(session.mapController.camera.rotation, 0);
      // A later manual rotation must survive fresh GPS and more browsing.
      session.mapController.rotate(32);
      navigation.pauseFollowForMapGesture();
      navigation.resetNorthAfterFocusExit();
      now = now.add(const Duration(seconds: 30));
      session.lastGpsUserLocationAt = now;
      session.currentUserHeadingDegrees = 180;
      navigation.updatePredictedUserMarker();
      navigation.updateFollowCamera(const LatLng(57, 25), 180);
      expect(session.mapController.camera.rotation, 32);
      expect(session.mapCenteredOnCurrentUser, isFalse);
      // Explicitly re-entering focus restores course-up navigation.
      session.mapCenteredOnCurrentUser = true;
      navigation.updatePredictedUserMarker();
      expect(
        normalizedRotationDegrees(
          session.mapController.camera.rotation +
              session.displayedNavigationHeading,
        ),
        closeTo(0, 0.001),
      );
      expect(session.mapController.camera.zoom, 15);
      await tester.pumpWidget(const SizedBox());
      session.mapController.dispose();
    },
  );
}
