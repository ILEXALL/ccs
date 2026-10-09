import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/spots/models/spot_categories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lossless artwork is bundled and decodes for Flutter and map markers',
    () async {
      for (final path in {
        'assets/xp_wheels/lvl_1.webp',
        'assets/xp_wheels/lvl_10.webp',
        'assets/xp_wheels/lvl_100.webp',
        'assets/xp_wheels/lvl_20.webp',
        'assets/xp_wheels/lvl_30.webp',
        'assets/xp_wheels/lvl_40.webp',
        'assets/xp_wheels/lvl_50.webp',
        'assets/xp_wheels/lvl_60.webp',
        'assets/xp_wheels/lvl_70.webp',
        'assets/xp_wheels/lvl_80.webp',
        'assets/xp_wheels/lvl_90.webp',
        'assets/bg.webp',
        'assets/bg_map.webp',
        'assets/ccs_logo.webp',
        ...spotCategoryIconAssets.values,
        ...spotCategoryLightIconAssets.values,
      }) {
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          targetWidth: 128,
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 128, reason: path);
        expect(
          await frame.image.toByteData(format: ui.ImageByteFormat.png),
          isNotNull,
          reason: path,
        );
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
