import 'package:flutter/widgets.dart';
import 'remote_image_cache.dart';

/// Only newly downloaded images fade. Disk hits may decode asynchronously.
Widget fadeInLoadedImage(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  final widget = context.widget;
  return LoadedImageFade(
    cached: widget is Image
        ? imageWasCached(widget.image)
        : Future.value(false),
    frame: frame,
    child: child,
  );
}

class LoadedImageFade extends StatefulWidget {
  const LoadedImageFade({
    super.key,
    required this.cached,
    required this.frame,
    required this.child,
  });
  final Future<bool> cached;
  final int? frame;
  final Widget child;

  @override
  State<LoadedImageFade> createState() => _LoadedImageFadeState();
}

class _LoadedImageFadeState extends State<LoadedImageFade> {
  // Keep the original decision when the parent rebuilds after downloading.
  late final Future<bool> _cached = widget.cached;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _cached,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return Opacity(opacity: 0, child: widget.child);
      if (snapshot.data!) return widget.child;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.frame == null ? 0 : 1),
        duration: const Duration(seconds: 1),
        curve: Curves.easeInOut,
        child: widget.child,
        builder: (context, opacity, image) =>
            Opacity(opacity: opacity, child: image),
      );
    },
  );
}
