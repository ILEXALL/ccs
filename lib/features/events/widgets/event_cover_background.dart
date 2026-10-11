import 'package:ccs_app/shared/media/remote_image_cache.dart'
    show cachedAppImage;
import 'package:ccs_app/shared/media/image_fade.dart' show fadeInLoadedImage;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../spots/models/car_spot.dart';
import '../../spots/widgets/spot_photo.dart';

/// Blur only a small cover decode, never the foreground or the scrolling UI.
class EventCoverBackground extends StatelessWidget {
  const EventCoverBackground({
    super.key,
    required this.spot,
    required this.child,
  });
  final CarSpot spot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!spot.isTemporary) return child;
    final sources = spotPhotoSources(spot);
    final source = sources.isEmpty ? null : sources.first;
    final ImageProvider? provider = source == null
        ? null
        : isLocalSpotPhotoSource(source)
        ? FileImage(File(localPhotoPathFromSource(source)))
        : cachedAppImage(source);
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF493722), Color(0xFF151923)],
            ),
          ),
        ),
        if (provider != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 48,
                      sigmaY: 48,
                      tileMode: TileMode.clamp,
                    ),
                    child: Image(
                      key: ValueKey(source),
                      frameBuilder: fadeInLoadedImage,
                      image: ResizeImage(
                        provider,
                        width: 192,
                        height: 192,
                        policy: ResizeImagePolicy.fit,
                      ),
                      // Stretch the already blurred colour field so the entire
                      // poster palette remains visible, including its edges.
                      fit: BoxFit.fill,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x59080B10),
                  Color(0x73080B10),
                  Color(0xA6080B10),
                ],
                stops: [0, .55, 1],
              ),
            ),
          ),
        ),
        // A faint neutral veil lifts crushed blacks without tinting the poster
        // or controls, which are painted above this background-only layer.
        const IgnorePointer(child: ColoredBox(color: Color(0x244E5056))),
        child,
      ],
    );
  }
}
