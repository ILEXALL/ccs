import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show photoPickerChannel;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/shared/media/photo_crop_screen.dart'
    show PhotoCropScreen;
import 'package:ccs_app/shared/media/photo_crop_shape.dart' show PhotoCropShape;

Future<String?> pickPhotoFromPhone(
  BuildContext context, {
  double cropAspectRatio = 1,
  PhotoCropShape cropShape = PhotoCropShape.rectangle,
  bool cropPhoto = true,
}) async {
  try {
    final path = await photoPickerChannel.invokeMethod<String>('pickPhoto');

    if (!context.mounted || path == null || path.trim().isEmpty || !cropPhoto) {
      return path;
    }

    return Navigator.push<String>(
      context,
      appPageRoute(
        builder: (_) => PhotoCropScreen(
          sourcePath: path,
          cropAspectRatio: cropAspectRatio,
          cropShape: cropShape,
        ),
      ),
    );
  } on PlatformException catch (error) {
    if (!context.mounted) {
      return null;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          error.message ?? 'Could not open photo picker.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return null;
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Photo picker is not connected in the native app.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return null;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not open photo picker. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return null;
  }
}
