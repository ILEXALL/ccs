import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/visit_dwell_marker.dart';

void main() {
  test(
    'visual interpolation never completes before server confirmation and expires',
    () {
      final now = DateTime(2026);
      final p = VisitDwellProgress(
        userId: 'u',
        spotId: 's',
        elapsedMs: 295000,
        requiredMs: 300000,
        completed: false,
        receivedAt: now,
      );
      expect(p.fraction(now.add(const Duration(seconds: 10))), .99);
      expect(p.fraction(now.add(const Duration(seconds: 61))), 0);
      final done = VisitDwellProgress(
        userId: 'u',
        spotId: 's',
        elapsedMs: 300000,
        requiredMs: 300000,
        completed: true,
        receivedAt: now,
      );
      expect(done.fraction(now), 1);
    },
  );
  testWidgets(
    'dwell ring keeps spot tappable and only server completion makes it green',
    (tester) async {
      var taps = 0;
      Future<void> render(bool completed) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 64,
                height: 64,
                child: VisitDwellMarker(
                  label: 'Оставайся 5 минут',
                  progress: VisitDwellProgress(
                    userId: 'u',
                    spotId: 's',
                    elapsedMs: completed ? 300000 : 150000,
                    requiredMs: 300000,
                    completed: completed,
                    receivedAt: DateTime.now(),
                  ),
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: const ColoredBox(
                      color: Colors.blue,
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await render(false);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        closeTo(.5, .01),
      );
      await tester.tap(find.byType(VisitDwellMarker));
      expect(taps, 1);
      await render(true);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .color,
        Colors.greenAccent,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
