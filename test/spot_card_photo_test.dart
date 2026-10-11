import 'dart:io';
import 'package:image/image.dart' as img;
import 'group_temporary_spots_test.dart' show event;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/spots/widgets/spot_card_photo.dart';

void main() {
  testWidgets(
    'decoded photo fades for one second and does not restart on rebuild',
    (tester) async {
      late Directory directory;
      late File file;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('ccs-card-fade-');
        file = File('${directory.path}/photo.png');
        final image = img.Image(width: 20, height: 30);
        img.fill(image, color: img.ColorRgb8(40, 110, 170));
        await file.writeAsBytes(img.encodePng(image));
      });
      final spot = event().copyWith(localPhotoPath: file.path);
      Widget card() => MaterialApp(
        home: Center(
          child: SpotCardPhoto(
            spot: spot,
            width: 100,
            height: 140,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      await tester.pumpWidget(card());
      for (
        var i = 0;
        i < 50 &&
            find
                    .descendant(
                      of: find.byType(SpotCardPhoto),
                      matching: find.byType(FadeTransition),
                    )
                    .evaluate()
                    .length <
                2;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        find.descendant(
          of: find.byType(SpotCardPhoto),
          matching: find.byType(FadeTransition),
        ),
        findsNWidgets(2),
      );
      double opacity() => tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: find.byType(SpotCardPhoto),
                  matching: find.byType(FadeTransition),
                )
                .last,
          )
          .opacity
          .value;
      expect(opacity(), closeTo(0, .01));
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacity(), closeTo(.5, .05));
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacity(), 1);
      await tester.pumpWidget(card());
      expect(opacity(), 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => directory.delete(recursive: true));
      expect(tester.takeException(), isNull);
    },
  );

  Uint8List photo({int top = 0, int bottom = 0, int left = 0, int right = 0}) {
    final pixels = Uint8List(100 * 100 * 4);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 100; x++) {
        final i = (y * 100 + x) * 4;
        final content =
            y >= top && y < 100 - bottom && x >= left && x < 100 - right;
        pixels[i] = content ? 80 : 0;
        pixels[i + 1] = content ? 120 : 0;
        pixels[i + 2] = content ? 60 : 0;
        pixels[i + 3] = 255;
      }
    }
    return pixels;
  }

  test('recognizes embedded horizontal and vertical framing bars', () {
    expect(
      spotPhotoContentRect(photo(top: 25, bottom: 25), 100, 100),
      const Rect.fromLTRB(0, 25, 100, 75),
    );
    expect(
      spotPhotoContentRect(photo(left: 20, right: 20), 100, 100),
      const Rect.fromLTRB(20, 0, 80, 100),
    );
  });
  test(
    'preserves unpadded images, one-sided shadows and entirely black photos',
    () {
      const full = Rect.fromLTWH(0, 0, 100, 100);
      expect(spotPhotoContentRect(photo(), 100, 100), full);
      expect(spotPhotoContentRect(photo(top: 25), 100, 100), full);
      expect(spotPhotoContentRect(Uint8List(100 * 100 * 4), 100, 100), full);
    },
  );
  test('does not treat dark photographic detail as uniform padding', () {
    final pixels = photo(top: 25, bottom: 25);
    for (var y = 0; y < 100; y++) {
      pixels[(y * 100 + 50) * 4] = 20;
    }
    expect(
      spotPhotoContentRect(pixels, 100, 100),
      const Rect.fromLTWH(0, 0, 100, 100),
    );
  });
}
