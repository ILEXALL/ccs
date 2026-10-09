import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

const int xpMaxLevel = 100;

const Map<int, String> xpWheelAssetByTier = {
  1: 'assets/xp_wheels/lvl_1.webp',
  10: 'assets/xp_wheels/lvl_10.webp',
  20: 'assets/xp_wheels/lvl_20.webp',
  30: 'assets/xp_wheels/lvl_30.webp',
  40: 'assets/xp_wheels/lvl_40.webp',
  50: 'assets/xp_wheels/lvl_50.webp',
  60: 'assets/xp_wheels/lvl_60.webp',
  70: 'assets/xp_wheels/lvl_70.webp',
  80: 'assets/xp_wheels/lvl_80.webp',
  90: 'assets/xp_wheels/lvl_90.webp',
  100: 'assets/xp_wheels/lvl_100.webp',
};

// Tire bounds in the 512px assets, excluding the decorative ring and label.
const Map<int, Rect> xpWheelBoundsByTier = {
  1: Rect.fromLTWH(119, 79, 273, 273),
  10: Rect.fromLTWH(119, 89, 274, 274),
  20: Rect.fromLTWH(118, 86, 276, 276),
  30: Rect.fromLTWH(109, 81, 294, 294),
  40: Rect.fromLTWH(97, 71, 318, 318),
  50: Rect.fromLTWH(96, 70, 320, 320),
  60: Rect.fromLTWH(94, 66, 324, 324),
  70: Rect.fromLTWH(76, 56, 360, 360),
  80: Rect.fromLTWH(73, 51, 366, 366),
  90: Rect.fromLTWH(74, 50, 364, 364),
  100: Rect.fromLTWH(80, 40, 356, 356),
};

const Map<int, Color> xpWheelAccentColorByTier = {
  1: Color(0xFF8C715A),
  10: Color(0xFF7B93C4),
  20: Color(0xFF457ECC),
  30: Color(0xFF356BD3),
  40: Color(0xFF5749D7),
  50: Color(0xFF8347DA),
  60: Color(0xFF803BD6),
  70: Color(0xFFDC41A3),
  80: Color(0xFFE29032),
  90: Color(0xFFD9B561),
  100: Color(0xFFD9A246),
};

int xpWheelTierForLevel(int level) {
  final safeLevel = math.min(xpMaxLevel, math.max(1, level)).toInt();
  if (safeLevel >= 100) {
    return 100;
  }
  if (safeLevel < 10) {
    return 1;
  }

  return (safeLevel ~/ 10) * 10;
}

String xpWheelAssetForLevel(int level) {
  return xpWheelAssetByTier[xpWheelTierForLevel(level)] ??
      xpWheelAssetByTier[1]!;
}

Color xpWheelAccentColorForLevel(int level) {
  return xpWheelAccentColorByTier[xpWheelTierForLevel(level)] ?? blue;
}

int xpRequiredForLevel(int level) {
  final safeLevel = math.min(xpMaxLevel, math.max(1, level)).toInt();
  return 25 * math.pow(safeLevel - 1, 2).round();
}

int xpLevelFromTotal(int totalXp) {
  if (totalXp <= 0) {
    return 1;
  }

  return math
      .min(xpMaxLevel, math.max(1, math.sqrt(totalXp / 25).floor() + 1))
      .toInt();
}

String formatXpValue(int value) {
  final safeValue = math.max(0, value);

  if (safeValue >= 1000000) {
    final formatted = (safeValue / 1000000).toStringAsFixed(
      safeValue >= 10000000 ? 0 : 1,
    );
    return '${formatted.replaceAll('.0', '')}M';
  }

  if (safeValue >= 10000) {
    return '${(safeValue / 1000).round()}K';
  }

  if (safeValue >= 1000) {
    final formatted = (safeValue / 1000).toStringAsFixed(1);
    return '${formatted.replaceAll('.0', '')}K';
  }

  return '$safeValue';
}
