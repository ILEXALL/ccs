import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/shared/media/local_files.dart' show localFileExists;
import 'package:ccs_app/shared/media/media_upload.dart' show isNetworkUrl;

Widget garagePhotoImage(
  String source, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) {
  if (localFileExists(source)) {
    return Image.file(
      File(source),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const GaragePhotoFallback(),
    );
  }

  if (isNetworkUrl(source)) {
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => const GaragePhotoFallback(),
    );
  }

  return const GaragePhotoFallback();
}

class GaragePhotoFallback extends StatelessWidget {
  const GaragePhotoFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white10,
      child: const Icon(Icons.directions_car, color: blue, size: 54),
    );
  }
}
