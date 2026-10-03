import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show
        maxGaragePhotos,
        maxSpotGalleryPhotos,
        r2AvatarPhotoMaxLongSide,
        r2GaragePhotoMaxLongSide,
        r2JpegQuality,
        r2SpotPhotoMaxLongSide;
import 'package:ccs_app/shared/media/media_upload.dart'
    show safeR2Path, uploadImageToR2;

Future<String> uploadSpotPhoto({
  required String spotId,
  required String localPhotoPath,
  required String userId,
  required int photoIndex,
}) async {
  if (photoIndex < 0 || photoIndex >= maxSpotGalleryPhotos) {
    throw Exception('Spot photo index is outside the allowed gallery range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  // Keep ownership in the object key even when the spot write fails or a
  // moderator later removes its Firestore document. Account deletion can then
  // remove every upload without relying on a surviving spot document.
  final r2Path =
      'users/${safeR2Path(userId)}/spot_photos/${safeR2Path(spotId)}/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2SpotPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadUserAvatarPhoto({
  required String userId,
  required String localPhotoPath,
}) async {
  final r2Path = 'users/$userId/avatar.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2AvatarPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadGroupAvatarPhoto({
  required String groupId,
  required String localPhotoPath,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final userId = firebaseUser?.uid.trim() ?? '';

  if (userId.isEmpty) {
    throw Exception('Log in before updating a group photo.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  // Keep group avatars under an existing user upload root. Some R2 presign
  // backends reject a direct groups/ root with "Invalid upload path".
  final r2Path =
      'users/${safeR2Path(userId)}/group_avatars/${safeR2Path(groupId)}/avatar_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2AvatarPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadForumTopicAvatarPhoto({
  required String userId,
  required String localPhotoPath,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = 'users/$userId/forum_topic_avatar_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2AvatarPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}

Future<String> uploadGarageCarPhoto({
  required String userId,
  required int carIndex,
  required int photoIndex,
  required String localPhotoPath,
}) async {
  if (photoIndex < 0 || photoIndex >= maxGaragePhotos) {
    throw Exception('Garage photo index is outside the allowed range.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final r2Path = photoIndex == 0
      ? 'garage/$userId/car_${carIndex}_cover.jpg'
      : 'garage/$userId/car_$carIndex/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: r2GaragePhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}
