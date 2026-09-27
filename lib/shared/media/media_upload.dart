import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:ccs_app/core/config/app_config.dart'
    show
        chatAttachmentMaxBytes,
        chatAttachmentTargetBytes,
        r2ChatAttachmentPhotoMaxLongSide,
        r2JpegQuality,
        r2PresignUploadUrl,
        r2SpotPhotoMaxLongSide;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;
import 'package:ccs_app/shared/media/photo_processing.dart'
    show decodePhotoImageBytes;

bool isNetworkUrl(String? value) {
  final cleanValue = value?.trim() ?? '';
  return cleanValue.startsWith('http://') || cleanValue.startsWith('https://');
}

String imageContentTypeForPath(String path) {
  // R2 uploads are normalized to compressed JPEGs to keep storage and bandwidth low.
  return 'image/jpeg';
}

String imageExtensionForPath(String path) {
  // Keep all uploaded images as JPG, even if the original phone image was PNG/WEBP.
  return 'jpg';
}

String safeR2Path(String value) {
  final clean = value
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+'), '/');

  return clean.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_');
}

Future<List<int>> compressedJpegBytesFromFile(
  String localPhotoPath, {
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final file = File(localPhotoPath);

  if (!await file.exists()) {
    throw Exception('Selected image file was not found on this phone.');
  }

  final originalBytes = await file.readAsBytes();
  var normalized = await decodePhotoImageBytes(originalBytes);

  if (normalized == null) {
    throw Exception('Could not read selected image. Try another photo.');
  }
  final longestSide = math.max(normalized.width, normalized.height);

  if (longestSide > maxLongSide) {
    final scale = maxLongSide / longestSide;
    normalized = img.copyResize(
      normalized,
      width: math.max(1, (normalized.width * scale).round()),
      height: math.max(1, (normalized.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  return img.encodeJpg(normalized, quality: quality);
}

Future<List<int>> compressedChatAttachmentJpegBytesFromFile(
  String localPhotoPath,
) async {
  final file = File(localPhotoPath);

  if (!await file.exists()) {
    throw Exception('Selected image file was not found on this phone.');
  }

  final originalBytes = await file.readAsBytes();
  final source = await decodePhotoImageBytes(originalBytes);

  if (source == null) {
    throw Exception('Could not read selected image. Try another photo.');
  }
  var maxLongSide = r2ChatAttachmentPhotoMaxLongSide;
  var quality = 84;
  List<int> bestBytes = const <int>[];

  for (var attempt = 0; attempt < 10; attempt++) {
    var candidate = source;
    final longestSide = math.max(candidate.width, candidate.height);
    if (longestSide > maxLongSide) {
      final scale = maxLongSide / longestSide;
      candidate = img.copyResize(
        candidate,
        width: math.max(1, (candidate.width * scale).round()),
        height: math.max(1, (candidate.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
    }

    final bytes = img.encodeJpg(candidate, quality: quality);
    bestBytes = bytes;

    if (bytes.length <= chatAttachmentMaxBytes) {
      if (bytes.length >= 180 * 1024 || quality <= 70 || maxLongSide <= 960) {
        return bytes;
      }
    }

    if (bytes.length > chatAttachmentTargetBytes) {
      if (quality > 72) {
        quality -= 6;
      } else {
        maxLongSide = (maxLongSide * 0.86).round().clamp(720, 1280).toInt();
        quality = 78;
      }
    } else {
      return bytes;
    }
  }

  return bestBytes;
}

Future<void> putBytesToPresignedUrl({
  required String uploadUrl,
  required List<int> bytes,
  required String contentType,
  String? cacheControl,
}) async {
  final client = HttpClient();

  try {
    final request = await client.putUrl(Uri.parse(uploadUrl));
    request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    if (cacheControl != null && cacheControl.isNotEmpty) {
      request.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
    }
    request.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close();
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('R2 upload failed ${response.statusCode}: $responseBody');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> uploadImageBytesToR2({
  required String r2Path,
  required List<int> bytes,
  String contentType = 'image/jpeg',
}) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null || token.isEmpty) {
    throw StateError('Sign in before uploading a photo.');
  }
  final presignData = await postJsonToUrl(
    r2PresignUploadUrl,
    {'path': safeR2Path(r2Path), 'contentType': contentType},
    headers: {'Authorization': 'Bearer $token'},
    logResponse: false,
  );

  final uploadUrl = stringFromFirebase(presignData['uploadUrl'], '');
  final publicUrl = stringFromFirebase(presignData['publicUrl'], '');

  if (uploadUrl.isEmpty || publicUrl.isEmpty) {
    throw Exception('R2 backend did not return upload URL.');
  }

  await putBytesToPresignedUrl(
    uploadUrl: uploadUrl,
    bytes: bytes,
    contentType: contentType,
    cacheControl: stringFromFirebase(presignData['cacheControl'], ''),
  );

  return publicUrl;
}

Future<String> uploadImageToR2({
  required String r2Path,
  required String localPhotoPath,
  int maxLongSide = r2SpotPhotoMaxLongSide,
  int quality = r2JpegQuality,
}) async {
  final bytes = await compressedJpegBytesFromFile(
    localPhotoPath,
    maxLongSide: maxLongSide,
    quality: quality,
  );

  return uploadImageBytesToR2(
    r2Path: r2Path,
    bytes: bytes,
    contentType: 'image/jpeg',
  );
}
