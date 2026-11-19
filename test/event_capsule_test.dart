import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/map/widgets/event_capsule.dart';
import 'package:ccs_app/features/map/models/event_marker_clusters.dart';

void main() {
  test('event metrics use spot scale and compact blue dots', () {
    expect(EventMarkerMetrics(6).dot, isTrue);
    expect(EventMarkerMetrics(6).width, lessThan(5));
    expect(EventMarkerMetrics(11.25).dot, isFalse);
    expect(EventMarkerMetrics(11.25).width, closeTo(30.4, .001));
    expect(EventMarkerMetrics(16).width, 65);
    expect(EventMarkerMetrics(13.9).showTime, isFalse);
    expect(EventMarkerMetrics(14).showTime, isTrue);
  });
  test('screen proximity chains keep all members; zoom splits them', () {
    const points = [
      Offset(0, 0),
      Offset(70, 0),
      Offset(140, 0),
      Offset(0, 100),
    ];
    final groups = groupEventMarkers(points, (p) => p, width: 88, height: 52);
    expect(groups.map((g) => g.length), [3, 1]);
    expect(
      groupEventMarkers(points, (p) => p * 2, width: 88, height: 52).length,
      4,
    );
    expect(
      groupEventMarkers(
        [Offset.zero, Offset.zero],
        (p) => p,
        width: 88,
        height: 52,
      ).single.length,
      2,
    );
  });
  testWidgets(
    'Capsule asset, count/time, small tap targets and dark/light rendering',
    (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previewOutput = Platform.environment['CCS_MARKER_PREVIEW'];
      if (previewOutput != null) {
        await tester.runAsync(() async {
          final loader = FontLoader('Preview');
          loader.addFont(
            File(
              r'C:\Windows\Fonts\segoeui.ttf',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        });
      }
      var taps = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: previewOutput == null ? null : 'Preview',
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Row(
                children: [
                  for (final light in [false, true])
                    Expanded(
                      child: Container(
                        color: light
                            ? const Color(0xffe7eceb)
                            : const Color(0xff17202a),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Text(
                              light ? 'CCS LIGHT' : 'CCS DARK',
                              style: TextStyle(
                                color: light ? Colors.black87 : Colors.white70,
                              ),
                            ),
                            EventCapsule(
                              light: light,
                              label: '20.11\n19:00',
                              width: 65,
                              onTap: () => taps++,
                            ),
                            EventCapsule(
                              light: light,
                              label: '×3',
                              width: 65,
                              onTap: () => taps++,
                            ),
                            EventCapsule(
                              light: light,
                              label: '',
                              width: 30.4,
                              onTap: () => taps++,
                            ),
                            Text(
                              '65px at zoom 16 · 30px at zoom 11.25',
                              style: TextStyle(
                                color: light ? Colors.black54 : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final light in [false, true]) {
          await precacheImage(
            AssetImage(
              'assets/globe/event-capsule-${light ? 'light' : 'dark'}.png',
            ),
            key.currentContext!,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('×3'), findsNWidgets(2));
      expect(find.text('20.11\n19:00'), findsNWidgets(2));
      for (final element in find.byType(EventCapsule).evaluate()) {
        final finder = find.byWidget(element.widget);
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
        await tester.tap(finder);
      }
      expect(taps, 6);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['CCS_MARKER_PREVIEW'];
      if (output != null) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
  testWidgets(
    'zoomed-out event uses a blue dot and retains a 44px hit target',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventCapsule(
              light: true,
              label: '',
              width: 4,
              dot: true,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      final dot = tester.widget<Container>(find.byType(Container).first);
      expect((dot.decoration as BoxDecoration).color, const Color(0xff1457ef));
      expect(
        tester.getSize(find.byType(EventCapsule)).width,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byType(EventCapsule));
      expect(taps, 1);
    },
  );
}
