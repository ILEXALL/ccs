import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show r2AvatarPhotoMaxLongSide, r2JpegQuality, r2SpotPhotoMaxLongSide;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/partners/models/partner.dart' show CcsPartner;
import 'package:ccs_app/shared/media/media_upload.dart'
    show safeR2Path, uploadImageToR2;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

CollectionReference<Map<String, dynamic>> ccsPartnersCollection() =>
    FirebaseFirestore.instance.collection('partners');

bool get currentUserCanManagePartners => currentUser.role == UserRole.admin;

List<CcsPartner> sortedPartners(
  QuerySnapshot<Map<String, dynamic>> snapshot, {
  bool includeInactive = false,
}) {
  final partners = snapshot.docs
      .map(CcsPartner.fromFirestore)
      .where(
        (partner) =>
            (includeInactive || partner.active) &&
            partner.name.trim().isNotEmpty &&
            partner.logoUrl.trim().isNotEmpty,
      )
      .toList();
  partners.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    final createdCompare = a.createdAtMillis.compareTo(b.createdAtMillis);
    if (createdCompare != 0) return createdCompare;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return partners;
}

List<CcsPartner> sortedVisiblePartners(
  QuerySnapshot<Map<String, dynamic>> snapshot,
) => sortedPartners(snapshot);

Future<String> uploadPartnerImage({
  required String partnerId,
  required String localPhotoPath,
  required bool logo,
  int photoIndex = 0,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final userId = firebaseUser?.uid.trim() ?? '';
  if (userId.isEmpty || currentUser.uid != userId) {
    throw StateError('Please sign in again before uploading partner media.');
  }
  if (!currentUserCanManagePartners) {
    throw StateError('Only administrators can manage partners.');
  }
  if (!logo && (photoIndex < 0 || photoIndex >= 4)) {
    throw StateError('Partner gallery supports up to 4 photos.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  // Keep partner media under the already-supported users/ upload root so the
  // current R2 presign endpoint does not need a new top-level upload path.
  final root = 'users/${safeR2Path(userId)}/partners/${safeR2Path(partnerId)}';
  final r2Path = logo
      ? '$root/logo_$timestamp.jpg'
      : '$root/gallery/photo_${photoIndex + 1}_$timestamp.jpg';

  return uploadImageToR2(
    r2Path: r2Path,
    localPhotoPath: localPhotoPath,
    maxLongSide: logo ? r2AvatarPhotoMaxLongSide : r2SpotPhotoMaxLongSide,
    quality: r2JpegQuality,
  );
}
