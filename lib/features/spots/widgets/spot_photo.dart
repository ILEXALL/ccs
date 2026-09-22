import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'dart:io';
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;

List<String> spotPhotoSources(CarSpot spot) {
  final sources = <String>[];

  void addSource(String value) {
    final trimmed = value.trim();

    if (trimmed.isNotEmpty && !sources.contains(trimmed)) {
      sources.add(trimmed);
    }
  }

  if (localFileExists(spot.localPhotoPath)) {
    addSource('local:${spot.localPhotoPath}');
  }

  for (final photoUrl in spot.photoUrls) {
    addSource(photoUrl);
  }

  addSource(spot.photoUrl);

  return sources;
}

bool isLocalSpotPhotoSource(String source) {
  return source.startsWith('local:');
}

String localPhotoPathFromSource(String source) {
  return source.substring('local:'.length);
}

Widget spotPhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (isLocalSpotPhotoSource(source)) {
    return Image.file(
      File(localPhotoPathFromSource(source)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) =>
          SpotPhotoPlaceholder(width: width, height: height),
    );
  }

  return Image.network(
    source,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, _, _) =>
        SpotPhotoPlaceholder(width: width, height: height),
  );
}

class SpotPhotoPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;

  const SpotPhotoPlaceholder({super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue),
    );
  }
}

class SpotPhoto extends StatelessWidget {
  final CarSpot spot;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SpotPhoto({
    super.key,
    required this.spot,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final sources = spotPhotoSources(spot);
    final photo = sources.isEmpty
        ? SpotPhotoPlaceholder(width: width, height: height)
        : spotPhotoImage(sources.first, width: width, height: height, fit: fit);

    if (borderRadius == null) {
      return photo;
    }

    return ClipRRect(borderRadius: borderRadius!, child: photo);
  }
}
