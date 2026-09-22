import 'dart:math' as math;

import 'package:ccs_app/features/map/widgets/exclusive_map_gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final zoomFirst in [true, false]) {
    testWidgets(
      '${zoomFirst ? 'zoom' : 'rotation'} locks until fingers are lifted',
      (tester) async {
        final controller = MapController();
        await tester.pumpWidget(
          MaterialApp(
            home: ExclusiveMapGestures(
              mapController: controller,
              builder: (options, constraint) => FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: const LatLng(56.95, 24.1),
                  initialZoom: 12,
                  initialRotation: 25,
                  minZoom: 3,
                  maxZoom: 18,
                  interactionOptions: options,
                  cameraConstraint: constraint,
                ),
                children: const [],
              ),
            ),
          ),
        );
        await tester.pump();
        final center = tester.getCenter(find.byType(FlutterMap));

        Future<void> gesture(bool zoom, {bool cancel = false}) async {
          final beforeZoom = controller.camera.zoom;
          final beforeRotation = controller.camera.rotation;
          final left = await tester.startGesture(
            center - const Offset(80, 0),
            pointer: 1,
          );
          final right = await tester.startGesture(
            center + const Offset(80, 0),
            pointer: 2,
          );
          Future<void> move(double radius, double degrees) async {
            final radians = degrees * math.pi / 180;
            final vector =
                Offset(math.cos(radians), math.sin(radians)) * radius;
            await left.moveTo(center - vector);
            await right.moveTo(center + vector);
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.takeException(), isNull);
            if (zoom) {
              expect(
                controller.camera.rotation,
                closeTo(beforeRotation, 0.001),
              );
            } else {
              expect(controller.camera.zoom, closeTo(beforeZoom, 0.001));
            }
          }

          // Select the intended gesture gradually, then deliberately combine
          // scaling and twisting without lifting either finger.
          for (var step = 1; step <= 12; step++) {
            await move(zoom ? 80.0 + step * 5 : 80.0, zoom ? 0.0 : step * 4.0);
          }
          if (zoom) {
            controller.rotate(beforeRotation + 40);
            expect(controller.camera.rotation, closeTo(beforeRotation, 0.001));
            expect(controller.camera.zoom, greaterThan(beforeZoom + 0.2));
            for (var step = 1; step <= 12; step++) {
              await move(140 - step * 3, step * 4);
            }
          } else {
            controller.move(controller.camera.center, beforeZoom + 1);
            expect(controller.camera.zoom, closeTo(beforeZoom, 0.001));
            expect(
              (controller.camera.rotation - beforeRotation).abs(),
              greaterThan(15),
            );
            for (var step = 1; step <= 12; step++) {
              await move(80 + step * 5, 48.0 + step);
            }
          }
          if (cancel) {
            await left.cancel();
            await right.cancel();
          } else {
            await left.up();
            await right.up();
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await gesture(zoomFirst);
        await gesture(!zoomFirst, cancel: true);
        await gesture(zoomFirst);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  for (final zoomFirst in [true, false]) {
    testWidgets(
      'combined platform pan/zoom locks ${zoomFirst ? 'zoom' : 'rotation'}',
      (tester) async {
        final controller = MapController();
        await tester.pumpWidget(
          MaterialApp(
            home: ExclusiveMapGestures(
              mapController: controller,
              builder: (options, constraint) => FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: const LatLng(56.95, 24.1),
                  initialZoom: 12,
                  initialRotation: 25,
                  minZoom: 3,
                  maxZoom: 18,
                  interactionOptions: options,
                  cameraConstraint: constraint,
                ),
                children: const [],
              ),
            ),
          ),
        );
        await tester.pump();
        final center = tester.getCenter(find.byType(FlutterMap));
        final pointer = TestPointer(10, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(pointer.panZoomStart(center));
        for (var step = 1; step <= 12; step++) {
          await tester.sendEventToBinding(
            pointer.panZoomUpdate(
              center,
              scale: zoomFirst ? 1 + step * 0.1 : 1,
              rotation: zoomFirst ? 0 : step * 0.06,
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var step = 1; step <= 12; step++) {
          await tester.sendEventToBinding(
            pointer.panZoomUpdate(
              center,
              scale: 2.2 + step * 0.1,
              rotation: 0.72 + step * 0.06,
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            zoomFirst ? controller.camera.rotation : controller.camera.zoom,
            closeTo(zoomFirst ? 25 : 12, 0.001),
          );
          expect(tester.takeException(), isNull);
        }
        expect(
          zoomFirst ? controller.camera.zoom : controller.camera.rotation,
          isNot(closeTo(zoomFirst ? 12 : 25, 0.01)),
        );
        await tester.sendEventToBinding(pointer.panZoomEnd());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
