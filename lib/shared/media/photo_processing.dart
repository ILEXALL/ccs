import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

Future<img.Image?> decodePhotoImageBytes(Uint8List bytes) async {
  // The pure-Dart image decoder is fast and keeps EXIF metadata, so keep it as
  // the primary path. Some Samsung camera JPEGs contain valid restart/marker
  // sequences that certain image package versions reject (for example
  // "Unknown JPEG marker d7"). Flutter's platform codec can still decode those
  // files, so fall back to it rather than rejecting the user's photo.
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      return img.bakeOrientation(decoded);
    }
  } catch (error) {
    debugPrint(
      'Dart image decoder failed; using native codec fallback: $error',
    );
  }

  ui.Codec? codec;
  ui.Image? nativeImage;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    nativeImage = frame.image;
    final rgba = await nativeImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (rgba == null) {
      return null;
    }

    return img.Image.fromBytes(
      width: nativeImage.width,
      height: nativeImage.height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  } catch (error, stack) {
    debugPrint('Native photo decoder fallback failed: $error');
    debugPrint('$stack');
    return null;
  } finally {
    nativeImage?.dispose();
    codec?.dispose();
  }
}

// The source rectangle may extend beyond the photo when zoomed out. Preserve
// that framing with black padding, rather than silently cropping again on save.
img.Image renderFramedPhoto(img.Image source, Rect sourceFrame) {
  final outputScale = math.min(
    1.0,
    2048 / math.max(sourceFrame.width, sourceFrame.height),
  );
  final output = img.Image(
    width: math.max(1, (sourceFrame.width * outputScale).round()),
    height: math.max(1, (sourceFrame.height * outputScale).round()),
    numChannels: 3,
  );
  final visible = sourceFrame.intersect(
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
  );
  if (visible.isEmpty) return output;
  img.compositeImage(
    output,
    source,
    srcX: visible.left.floor(),
    srcY: visible.top.floor(),
    srcW: math.max(1, visible.width.floor()),
    srcH: math.max(1, visible.height.floor()),
    dstX: ((visible.left - sourceFrame.left) * outputScale).round(),
    dstY: ((visible.top - sourceFrame.top) * outputScale).round(),
    dstW: math.max(1, (visible.width * outputScale).round()),
    dstH: math.max(1, (visible.height * outputScale).round()),
  );
  return output;
}
