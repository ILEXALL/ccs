import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:ccs_app/features/map/models/map_style.dart'
    show CcsMapStyle, CcsMapStylePresentation;

class CcsSmoothMapTileLayer extends StatefulWidget {
  final CcsMapStyle mapStyle;

  const CcsSmoothMapTileLayer({super.key, required this.mapStyle});

  @override
  State<CcsSmoothMapTileLayer> createState() => _CcsSmoothMapTileLayerState();
}

class _CcsSmoothMapTileLayerState extends State<CcsSmoothMapTileLayer>
    with SingleTickerProviderStateMixin {
  static const transitionDuration = Duration(milliseconds: 650);

  late final AnimationController controller;
  late CcsMapStyle currentStyle;
  CcsMapStyle? previousStyle;

  @override
  void initState() {
    super.initState();
    currentStyle = widget.mapStyle;
    controller =
        AnimationController(vsync: this, duration: transitionDuration, value: 1)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && previousStyle != null) {
              setState(() => previousStyle = null);
            }
          });
  }

  @override
  void didUpdateWidget(covariant CcsSmoothMapTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.mapStyle == currentStyle) {
      return;
    }

    setState(() {
      previousStyle = currentStyle;
      currentStyle = widget.mapStyle;
    });
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget _tileLayer(CcsMapStyle style) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(style.tileColorMatrix),
      child: TileLayer(
        key: ValueKey('ccs-map-tiles-${style.name}-${style.tileUrl}'),
        urlTemplate: style.tileUrl,
        userAgentPackageName: 'com.example.ccs_app',
        maxNativeZoom: 19,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previous = previousStyle;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final progress = Curves.easeInOutCubic.transform(controller.value);

        return Stack(
          fit: StackFit.expand,
          children: [
            if (previous != null)
              Opacity(opacity: 1 - progress, child: _tileLayer(previous)),
            Opacity(
              opacity: previous == null ? 1 : progress,
              child: _tileLayer(currentStyle),
            ),
          ],
        );
      },
    );
  }
}
