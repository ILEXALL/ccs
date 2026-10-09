import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

const blue = Color(0xFF1565FF);

const ccsGradientStart = Color(0xFF0628C8);

const ccsGradientEnd = Color(0xFF00C8FF);

const ccsBlueCyanGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [ccsGradientStart, ccsGradientEnd],
);

const sosAlertColor = Color(0xFFFF2D55);

Color policeAlertColor(double pulse) {
  return Color.lerp(blue, sosAlertColor, pulse)!;
}

Color get night => const Color(0xFF050507);

Color get panel => const Color(0xFF101014);

Color get panelGlass => const Color(0xCC101014);

Color get panelGlassSoft => const Color(0xB0101014);

Color get appPrimaryText => Colors.white;

Color get appSecondaryText => Colors.white54;

Color get appSubtleText => Colors.white38;

Color get appOutline => Colors.white12;

Color get appSurfaceOverlay => Colors.white.withValues(alpha: 0.06);

const appMapBackgroundAsset = 'assets/bg_map.webp';

ui.Image? appMapBackgroundImage;

Future<void> warmUpAppMapBackground() async {
  try {
    final bytes = await rootBundle.load(appMapBackgroundAsset);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      targetWidth: 1440,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      appMapBackgroundImage = frame.image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    appMapBackgroundImage = null;
  }
}
