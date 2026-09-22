import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/map/models/map_style.dart'
    show CcsMapStyle, CcsMapStylePresentation;

class MapStyleSelector extends StatelessWidget {
  final CcsMapStyle selectedStyle;
  final bool adaptiveEnabled;
  final ValueChanged<CcsMapStyle> onSelected;
  final ValueChanged<bool> onAdaptiveChanged;
  final int filterEnabledCount;
  final int filterTotalCount;
  final VoidCallback onFilterTap;

  const MapStyleSelector({
    super.key,
    required this.selectedStyle,
    required this.adaptiveEnabled,
    required this.onSelected,
    required this.onAdaptiveChanged,
    required this.filterEnabledCount,
    required this.filterTotalCount,
    required this.onFilterTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final style in CcsMapStyle.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: selectedStyle == style
                      ? blue.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    onTap: () => onSelected(style),
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      height: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: selectedStyle == style
                              ? blue
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            style.icon,
                            size: 16,
                            color: selectedStyle == style
                                ? blue
                                : Colors.white60,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: CcsText(
                              style.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                color: selectedStyle == style
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Colors.white12,
          ),
          Tooltip(
            message: trText('Automatic map style'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CcsText(
                  'Auto',
                  style: TextStyle(
                    color: adaptiveEnabled ? blue : Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Transform.scale(
                  scale: 0.58,
                  child: Switch(
                    value: adaptiveEnabled,
                    activeThumbColor: blue,
                    onChanged: onAdaptiveChanged,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            color: Colors.white12,
          ),
          MapFilterButton(
            enabledCount: filterEnabledCount,
            totalCount: filterTotalCount,
            onTap: onFilterTap,
          ),
        ],
      ),
    );
  }
}

class MapFilterButton extends StatelessWidget {
  final int enabledCount;
  final int totalCount;
  final VoidCallback onTap;

  const MapFilterButton({
    super.key,
    required this.enabledCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allEnabled = enabledCount == totalCount;

    return Tooltip(
      message: trText('Map filters'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 38,
            height: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune,
                  color: allEnabled ? Colors.white70 : blue,
                  size: 19,
                ),
                if (!allEnabled)
                  const Positioned(
                    right: 5,
                    top: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: blue,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(width: 6, height: 6),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpotRouteDistanceBadge extends StatelessWidget {
  final String spotName;
  final String distanceLabel;
  final bool isLoading;

  const SpotRouteDistanceBadge({
    super.key,
    required this.spotName,
    required this.distanceLabel,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName = spotName.trim();

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: blue.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: blue),
                )
              : const Icon(Icons.route, color: blue, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  distanceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (cleanName.isNotEmpty)
                  CcsText(
                    cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SpotFogBucket {
  double latitudeTotal = 0;
  double longitudeTotal = 0;
  double redTotal = 0;
  double greenTotal = 0;
  double blueTotal = 0;
  int count = 0;

  SpotFogBucket();

  void add(LatLng point, Color color) {
    latitudeTotal += point.latitude;
    longitudeTotal += point.longitude;
    redTotal += color.r;
    greenTotal += color.g;
    blueTotal += color.b;
    count++;
  }

  LatLng get center {
    if (count <= 0) {
      return const LatLng(0, 0);
    }
    return LatLng(latitudeTotal / count, longitudeTotal / count);
  }

  Color get color {
    if (count <= 0) {
      return blue;
    }

    return Color.from(
      alpha: 1,
      red: (redTotal / count).clamp(0.0, 1.0),
      green: (greenTotal / count).clamp(0.0, 1.0),
      blue: (blueTotal / count).clamp(0.0, 1.0),
    );
  }
}

class SpotFogCloud extends StatelessWidget {
  final Color color;
  final int density;

  const SpotFogCloud({super.key, required this.color, this.density = 1});

  @override
  Widget build(BuildContext context) {
    final centerAlpha = (0.62 + math.min(0.16, density * 0.012))
        .clamp(0.0, 0.78)
        .toDouble();

    // One radial gradient only. The previous version stacked four separate
    // gradient widgets per cloud, which was unnecessarily expensive while the
    // map was moving.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            stops: const [0.0, 0.24, 0.52, 0.76, 1.0],
            colors: [
              color.withValues(alpha: centerAlpha),
              color.withValues(alpha: centerAlpha * 0.72),
              color.withValues(alpha: centerAlpha * 0.32),
              color.withValues(alpha: centerAlpha * 0.08),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactSpotMapPoint extends StatelessWidget {
  final Color color;
  final double size;
  final bool faded;
  final bool event;

  const CompactSpotMapPoint({
    super.key,
    required this.color,
    this.size = 14,
    this.faded = false,
    this.event = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: faded ? 0.58 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: event
                  ? Colors.orangeAccent
                  : Colors.white.withValues(alpha: 0.80),
              width: event
                  ? math.max(0.5, size * 0.09)
                  : math.max(0.45, size * 0.065),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: event ? 0.54 : 0.38),
                blurRadius: math.max(
                  event ? 3.2 : 2.4,
                  size * (event ? 0.50 : 0.38),
                ),
                spreadRadius: math.max(
                  event ? 0.28 : 0.18,
                  size * (event ? 0.055 : 0.04),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PulsingTemporarySpotIconGlow extends StatefulWidget {
  final double size;
  final Widget child;
  final bool compact;

  const PulsingTemporarySpotIconGlow({
    super.key,
    required this.size,
    required this.child,
    this.compact = false,
  });

  @override
  State<PulsingTemporarySpotIconGlow> createState() =>
      _PulsingTemporarySpotIconGlowState();
}

class _PulsingTemporarySpotIconGlowState
    extends State<PulsingTemporarySpotIconGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(controller.value);
        final scale = widget.compact ? 1 + value * 0.12 : 1 + value * 0.065;
        final glowBlur = widget.compact
            ? math.max(2.2, widget.size * (0.50 + value * 0.44))
            : math.max(12.0, widget.size * (0.30 + value * 0.16));
        final glowSpread = widget.compact
            ? math.max(0.10, widget.size * (0.04 + value * 0.05))
            : math.max(1.8, widget.size * (0.045 + value * 0.025));

        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orangeAccent.withValues(
                    alpha: widget.compact ? 0.55 : 0.62,
                  ),
                  blurRadius: glowBlur,
                  spreadRadius: glowSpread,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class MapHeader extends StatelessWidget {
  final bool isSharingLiveLocation;
  final bool isBusy;
  final ValueChanged<bool> onShareChanged;

  const MapHeader({
    super.key,
    required this.isSharingLiveLocation,
    required this.isBusy,
    required this.onShareChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSharingLiveLocation ? blue : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.near_me_outlined,
            size: 15,
            color: isSharingLiveLocation ? blue : Colors.white60,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: CcsText(
              'Share live location',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.72,
            child: Switch(
              value: isSharingLiveLocation,
              activeThumbColor: blue,
              onChanged: isBusy ? null : onShareChanged,
            ),
          ),
        ],
      ),
    );
  }
}
