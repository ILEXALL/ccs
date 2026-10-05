import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/theme/app_theme.dart' show night;

enum CcsMapStyle { dark, light }

const ccsMapStylePreferenceKey = 'ccs_map_style';

const ccsAdaptiveMapStylePreferenceKey = 'ccs_adaptive_map_style';

CcsMapStyle mapStyleForLocalTime(DateTime time) {
  return time.hour >= 7 && time.hour < 21
      ? CcsMapStyle.light
      : CcsMapStyle.dark;
}

extension CcsMapStylePresentation on CcsMapStyle {
  String get label {
    switch (this) {
      case CcsMapStyle.dark:
        return 'CCS Dark';
      case CcsMapStyle.light:
        return 'CCS Light';
    }
  }

  IconData get icon {
    switch (this) {
      case CcsMapStyle.dark:
        return Icons.dark_mode_outlined;
      case CcsMapStyle.light:
        return Icons.light_mode_outlined;
    }
  }

  Color get backgroundColor {
    return this == CcsMapStyle.light ? const Color(0xFF9EA4AA) : night;
  }

  Color get mapLabelColor {
    return this == CcsMapStyle.light ? const Color(0xFF101820) : Colors.white;
  }

  Color get mapMutedLabelColor {
    return this == CcsMapStyle.light ? const Color(0xFF31404E) : Colors.white54;
  }

  Color get mapLabelShadowColor {
    return this == CcsMapStyle.light
        ? Colors.white.withValues(alpha: 0.72)
        : Colors.black.withValues(alpha: 0.92);
  }

  List<double> get tileColorMatrix {
    if (this == CcsMapStyle.light) {
      // Neutral gray + contrast pass for CCS Light.
      // Rows sum equally for neutral land/roads/buildings so the whole map
      // does not get a blue wash, while the blue channel still reacts more
      // to real water so rivers/lakes/sea remain blue.
      return const [
        0.45,
        0.45,
        0.10,
        0,
        -64,
        0.38,
        0.50,
        0.12,
        0,
        -64,
        0.22,
        0.30,
        0.48,
        0,
        -64,
        0,
        0,
        0,
        1,
        0,
      ];
    }

    return const [
      1.20,
      0,
      0,
      0,
      0,
      0,
      1.20,
      0,
      0,
      0,
      0,
      0,
      1.20,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
