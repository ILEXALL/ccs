import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:image/image.dart' as img;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;
import 'package:ccs_app/shared/media/photo_processing.dart'
    show decodePhotoImageBytes, renderFramedPhoto;

class PhotoCropScreen extends StatefulWidget {
  final String sourcePath;
  final double cropAspectRatio;
  final PhotoCropShape cropShape;

  const PhotoCropScreen({
    super.key,
    required this.sourcePath,
    required this.cropAspectRatio,
    this.cropShape = PhotoCropShape.rectangle,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen>
    with LanguageReactiveState {
  double zoom = 1;
  Offset offset = Offset.zero;
  double editorWidth = 0;
  double editorHeight = 0;
  double cropWidth = 0;
  double cropHeight = 0;
  double gestureStartZoom = 1;
  int? imageWidth;
  int? imageHeight;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadImageSize();
  }

  Future<void> loadImageSize() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final normalized = await decodePhotoImageBytes(bytes);

      if (!mounted || normalized == null) {
        return;
      }

      setState(() {
        imageWidth = normalized.width;
        imageHeight = normalized.height;
        if (cropWidth > 0 && cropHeight > 0) {
          zoom = minZoomForLayout() * 4;
          offset = Offset.zero;
        }
      });
    } catch (_) {}
  }

  double minZoomForLayout() {
    final width = imageWidth;
    final height = imageHeight;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return 1;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    return math.max(
      0.01,
      0.25 *
          math.min(
            cropWidth / (width * baseScale),
            cropHeight / (height * baseScale),
          ),
    );
  }

  Offset clampedOffset(Offset value, {double? zoomValue}) {
    final width = imageWidth;
    final height = imageHeight;
    final currentZoom = zoomValue ?? zoom;

    if (width == null ||
        height == null ||
        editorWidth <= 0 ||
        editorHeight <= 0 ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      return value;
    }

    final baseScale = math.min(editorWidth / width, editorHeight / height);
    final displayWidth = width * baseScale * currentZoom;
    final displayHeight = height * baseScale * currentZoom;
    final cropLeft = (editorWidth - cropWidth) / 2;
    final cropTop = (editorHeight - cropHeight) / 2;
    final cropRight = cropLeft + cropWidth;
    final cropBottom = cropTop + cropHeight;
    final minX = cropRight - (editorWidth + displayWidth) / 2;
    final maxX = cropLeft - (editorWidth - displayWidth) / 2;
    final minY = cropBottom - (editorHeight + displayHeight) / 2;
    final maxY = cropTop - (editorHeight - displayHeight) / 2;

    // Depending on the photo aspect ratio, the image can be smaller than
    // the crop frame on one axis while the layout is settling. In that case
    // the calculated clamp bounds are reversed, and num.clamp throws an
    // "Invalid argument(s)" red-screen exception. Normalise the ranges and
    // keep non-finite gesture values from reaching Transform.translate.
    double clampAxis(double axisValue, double firstBound, double secondBound) {
      if (!axisValue.isFinite ||
          !firstBound.isFinite ||
          !secondBound.isFinite) {
        return 0.0;
      }

      final lower = math.min(firstBound, secondBound);
      final upper = math.max(firstBound, secondBound);
      return axisValue.clamp(lower, upper).toDouble();
    }

    return Offset(
      clampAxis(value.dx, minX, maxX),
      clampAxis(value.dy, minY, maxY),
    );
  }

  Future<void> saveCroppedPhoto() async {
    if (isSaving) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final file = File(widget.sourcePath);
      final bytes = await file.readAsBytes();
      final normalized = await decodePhotoImageBytes(bytes);

      if (normalized == null) {
        throw Exception('Could not read selected image.');
      }
      final width = normalized.width;
      final height = normalized.height;
      final hasLayout =
          editorWidth > 0 &&
          editorHeight > 0 &&
          cropWidth > 0 &&
          cropHeight > 0;
      final baseScale = hasLayout
          ? math.min(editorWidth / width, editorHeight / height)
          : 1.0;
      final effectiveZoom = math.max(zoom, minZoomForLayout());
      final totalScale = hasLayout ? baseScale * effectiveZoom : 1.0;
      final cropLeft = hasLayout ? (editorWidth - cropWidth) / 2 : 0.0;
      final cropTop = hasLayout ? (editorHeight - cropHeight) / 2 : 0.0;
      final imageLeft = hasLayout
          ? (editorWidth - width * totalScale) / 2 + offset.dx
          : 0.0;
      final imageTop = hasLayout
          ? (editorHeight - height * totalScale) / 2 + offset.dy
          : 0.0;
      final cropped = renderFramedPhoto(
        normalized,
        hasLayout
            ? Rect.fromLTWH(
                (cropLeft - imageLeft) / totalScale,
                (cropTop - imageTop) / totalScale,
                cropWidth / totalScale,
                cropHeight / totalScale,
              )
            : Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
      final directory = await Directory.systemTemp.createTemp('ccs_photo_');
      final croppedPath =
          '${directory.path}${Platform.pathSeparator}photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final croppedFile = File(croppedPath);

      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: 92));

      if (mounted) {
        Navigator.pop(context, croppedFile.path);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not prepare photo: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const CcsText('Adjust Photo'),
        backgroundColor: Colors.black,
        foregroundColor: blue,
        actions: [
          IconButton(
            tooltip: 'Use photo',
            onPressed: isSaving ? null : saveCroppedPhoto,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          editorWidth = (constraints.maxWidth - 40).clamp(260, 520).toDouble();
          editorHeight = math
              .min(constraints.maxHeight * 0.58, 560)
              .clamp(330, 560)
              .toDouble();
          final frameMaxWidth = editorWidth - 34;
          final frameMaxHeight = editorHeight - 70;
          final isCircleCrop = widget.cropShape == PhotoCropShape.circle;
          cropWidth = frameMaxWidth;
          final cropRatio = isCircleCrop
              ? 1.0
              : widget.cropAspectRatio <= 0
              ? 1.0
              : widget.cropAspectRatio;
          cropHeight = cropWidth / cropRatio;
          if (cropHeight > frameMaxHeight) {
            cropHeight = frameMaxHeight;
            cropWidth = cropHeight * cropRatio;
          }
          final minZoom = minZoomForLayout();
          final maxZoom = math.max(3.0, minZoom * 3);
          final effectiveZoom = zoom.clamp(minZoom, maxZoom).toDouble();
          if ((zoom - effectiveZoom).abs() > 0.001) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  zoom = effectiveZoom;
                  offset = clampedOffset(offset, zoomValue: effectiveZoom);
                });
              }
            });
          }
          offset = clampedOffset(offset, zoomValue: effectiveZoom);
          final cropLeft = (editorWidth - cropWidth) / 2;
          final cropTop = (editorHeight - cropHeight) / 2;
          final cropRightWidth = editorWidth - cropLeft - cropWidth;
          final cropBottomHeight = editorHeight - cropTop - cropHeight;

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              children: [
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) {
                      gestureStartZoom = effectiveZoom;
                    },
                    onScaleUpdate: (details) {
                      final nextZoom = (gestureStartZoom * details.scale)
                          .clamp(minZoom, maxZoom)
                          .toDouble();
                      setState(() {
                        zoom = nextZoom;
                        offset = clampedOffset(
                          offset + details.focalPointDelta,
                          zoomValue: nextZoom,
                        );
                      });
                    },
                    child: Container(
                      width: editorWidth,
                      height: editorHeight,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.translate(
                            offset: offset,
                            child: Transform.scale(
                              scale: effectiveZoom,
                              child: Image.file(
                                File(widget.sourcePath),
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.white38,
                                    size: 44,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            right: 0,
                            height: cropTop,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: cropTop,
                            width: cropLeft,
                            height: cropHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: cropTop,
                            width: cropRightWidth,
                            height: cropHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: cropBottomHeight,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            left: cropLeft,
                            top: cropTop,
                            child: IgnorePointer(
                              child: Container(
                                width: cropWidth,
                                height: cropHeight,
                                decoration: BoxDecoration(
                                  shape: isCircleCrop
                                      ? BoxShape.circle
                                      : BoxShape.rectangle,
                                  borderRadius: isCircleCrop
                                      ? null
                                      : BorderRadius.circular(12),
                                  border: Border.all(color: blue, width: 2),
                                ),
                                child: isCircleCrop
                                    ? const SizedBox.shrink()
                                    : Stack(
                                        children: [
                                          Center(
                                            child: Container(
                                              width: cropWidth,
                                              height: 1,
                                              color: Colors.white.withValues(
                                                alpha: 0.22,
                                              ),
                                            ),
                                          ),
                                          Center(
                                            child: Container(
                                              width: 1,
                                              height: cropHeight,
                                              color: Colors.white.withValues(
                                                alpha: 0.22,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          if (isCircleCrop)
                            Positioned(
                              left: cropLeft,
                              top: cropTop,
                              child: IgnorePointer(
                                child: Container(
                                  width: cropWidth,
                                  height: cropHeight,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.36,
                                        ),
                                        blurRadius: 18,
                                        spreadRadius: -6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: trText('Fit whole photo'),
                        icon: const Icon(
                          Icons.fit_screen,
                          color: Colors.white70,
                        ),
                        onPressed: isSaving
                            ? null
                            : () {
                                setState(() {
                                  zoom = minZoomForLayout() * 4;
                                  offset = Offset.zero;
                                });
                              },
                      ),
                      Expanded(
                        child: Slider(
                          value: effectiveZoom,
                          min: minZoom,
                          max: maxZoom,
                          activeColor: blue,
                          inactiveColor: Colors.white24,
                          onChanged: (value) {
                            setState(() {
                              zoom = value;
                              offset = clampedOffset(offset, zoomValue: value);
                            });
                          },
                        ),
                      ),
                      const Icon(Icons.zoom_in, color: Colors.white54),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : saveCroppedPhoto,
                    icon: const Icon(Icons.check),
                    label: CcsText(isSaving ? 'Saving...' : 'Use Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
