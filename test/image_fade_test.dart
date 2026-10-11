import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/shared/media/image_fade.dart';

void main() {
  testWidgets('new download waits for a frame and fades for one second', (
    tester,
  ) async {
    int? frame;
    var cached = false;
    Widget sample() => Directionality(
      textDirection: TextDirection.ltr,
      child: LoadedImageFade(
        cached: Future.value(cached),
        frame: frame,
        child: const SizedBox(width: 20, height: 20),
      ),
    );
    double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
    await tester.pumpWidget(sample());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(), 0);
    frame = 0;
    // Download has finished, but the original cache-miss decision must persist.
    cached = true;
    await tester.pumpWidget(sample());
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), closeTo(.5, .02));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), 1);
    await tester.pumpWidget(sample());
    expect(opacity(), 1);
  });

  testWidgets('asynchronous disk hit appears immediately without animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      LoadedImageFade(
        cached: Future.value(true),
        frame: 0,
        child: const SizedBox(width: 20, height: 20),
      ),
    );
    await tester.pump();
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('synchronous memory hit bypasses the fade', (tester) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) => fadeInLoadedImage(
          context,
          const SizedBox(width: 20, height: 20),
          0,
          true,
        ),
      ),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(LoadedImageFade), findsNothing);
  });
}
