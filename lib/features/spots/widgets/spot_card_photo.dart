import 'package:ccs_app/shared/media/remote_image_cache.dart'
    show cachedAppImage, imageWasCached;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/car_spot.dart';
import 'spot_photo.dart';

/// Only remove symmetric, nearly pure-black padding, not ordinary dark scenery.
Rect spotPhotoContentRect(Uint8List rgba, int width, int height) {
  bool black(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] <= 4 && rgba[i + 1] <= 4 && rgba[i + 2] <= 4;
  }

  bool row(int y) {
    var count = 0;
    for (var x = 0; x < width; x++) {
      if (black(x, y)) count++;
    }
    return count >= width * .995;
  }

  bool column(int x) {
    var count = 0;
    for (var y = 0; y < height; y++) {
      if (black(x, y)) count++;
    }
    return count >= height * .995;
  }

  var top = 0, bottom = 0, left = 0, right = 0;
  while (top < height * .38 && row(top)) {
    top++;
  }
  while (bottom < height * .38 && row(height - bottom - 1)) {
    bottom++;
  }
  while (left < width * .38 && column(left)) {
    left++;
  }
  while (right < width * .38 && column(width - right - 1)) {
    right++;
  }
  bool paired(int a, int b, int extent) =>
      a >= extent * .025 &&
      b >= extent * .025 &&
      (a - b).abs() <= extent * .025 &&
      a + b < extent * .72;
  if (!paired(top, bottom, height)) {
    top = 0;
    bottom = 0;
  }
  if (!paired(left, right, width)) {
    left = 0;
    right = 0;
  }
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (width - right).toDouble(),
    (height - bottom).toDouble(),
  );
}

class SpotCardPhoto extends StatefulWidget {
  const SpotCardPhoto({
    super.key,
    required this.spot,
    required this.width,
    required this.height,
    required this.borderRadius,
    this.echoOnly = false,
  });
  final CarSpot spot;
  final bool echoOnly;
  final double width, height;
  final BorderRadius borderRadius;
  @override
  State<SpotCardPhoto> createState() => _SpotCardPhotoState();
}

class _SpotCardPhotoState extends State<SpotCardPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeInOut,
  );
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  Rect? _sourceRect;
  String? _source;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SpotCardPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final sources = spotPhotoSources(widget.spot);
    final source = sources.isEmpty ? null : sources.first;
    if (source == _source) return;
    _source = source;
    _fade.reset();
    final generation = ++_generation;
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    _info = null;
    _sourceRect = null;
    if (source == null) return;
    final ImageProvider provider = isLocalSpotPhotoSource(source)
        ? FileImage(File(localPhotoPathFromSource(source)))
        : cachedAppImage(source);
    final cached = imageWasCached(provider);
    // Bounded decoding keeps the card's two paint passes inexpensive.
    _stream = ResizeImage(
      provider,
      width: 640,
      height: 640,
      policy: ResizeImagePolicy.fit,
    ).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (info, synchronousCall) async {
        try {
          final skipFade = synchronousCall || await cached;
          final data = await info.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (!mounted || generation != _generation) {
            info.dispose();
            return;
          }
          final rect = data == null
              ? null
              : spotPhotoContentRect(
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                  info.image.width,
                  info.image.height,
                );
          setState(() {
            _info?.dispose();
            _info = info;
            _sourceRect = rect;
          });
          if (skipFade) {
            _fade.value = 1;
          } else {
            _fade.forward();
          }
        } catch (_) {
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted && generation == _generation) setState(() {});
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    _generation++;
    if (_listener != null) _stream?.removeListener(_listener!);
    _info?.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.echoOnly)
            FadeTransition(
              opacity: ReverseAnimation(_opacity),
              child: const SpotPhotoPlaceholder(),
            ),
          if (_info != null)
            FadeTransition(
              opacity: _opacity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CardPhotoPainter(
                    _info!.image,
                    _sourceRect,
                    echoOnly: widget.echoOnly,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _CardPhotoPainter extends CustomPainter {
  const _CardPhotoPainter(this.image, this.sourceRect, {this.echoOnly = false});
  final bool echoOnly;
  final ui.Image image;
  final Rect? sourceRect;
  @override
  void paint(Canvas canvas, Size size) {
    final source =
        sourceRect ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final bounds = Offset.zero & size;
    void draw(BoxFit fit) {
      final fitted = applyBoxFit(fit, source.size, size);
      final crop = Alignment.center.inscribe(fitted.source, source);
      final destination = Alignment.center.inscribe(fitted.destination, bounds);
      canvas.drawImageRect(
        image,
        crop,
        destination,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    canvas.save();
    canvas.clipRect(bounds);
    final hasGaps =
        (source.width / source.height - size.width / size.height).abs() > .01;
    if (hasGaps || echoOnly) {
      canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: echoOnly ? 24 : 12,
            sigmaY: echoOnly ? 24 : 12,
            tileMode: TileMode.clamp,
          ),
      );
      draw(BoxFit.cover);
      canvas.restore();
      canvas.drawRect(bounds, Paint()..color = const Color(0x33000000));
    }
    if (!echoOnly) draw(BoxFit.contain);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPhotoPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.sourceRect != sourceRect ||
      oldDelegate.echoOnly != echoOnly;
}
