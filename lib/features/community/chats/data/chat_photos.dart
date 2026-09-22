import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/shared/media/media_upload.dart'
    show
        compressedChatAttachmentJpegBytesFromFile,
        safeR2Path,
        uploadImageBytesToR2;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;

Future<String> uploadChatAttachmentPhoto({
  required String scope,
  required String parentId,
  required String messageId,
  required String localPhotoPath,
}) async {
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final userId = firebaseUser?.uid.trim() ?? '';

  if (userId.isEmpty) {
    throw Exception('Log in before attaching a photo.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  // The R2 presign backend only accepts existing app upload roots such as
  // users/, spots/, garage/, and groups/. Store chat/forum attachments under
  // the sender's users/ folder instead of a new top-level chat_attachments/
  // folder, otherwise the backend returns: Invalid upload path.
  final r2Path =
      'users/${safeR2Path(userId)}/chat_attachments/${safeR2Path(scope)}/${safeR2Path(parentId)}/${safeR2Path(messageId)}_$timestamp.jpg';
  final bytes = await compressedChatAttachmentJpegBytesFromFile(localPhotoPath);

  return uploadImageBytesToR2(
    r2Path: r2Path,
    bytes: bytes,
    contentType: 'image/jpeg',
  );
}

Future<String?> pickAndUploadChatAttachmentPhoto({
  required BuildContext context,
  required String scope,
  required String parentId,
  required String messageId,
}) async {
  final path = await pickPhotoFromPhone(context, cropPhoto: false);
  if (path == null || path.trim().isEmpty) {
    return null;
  }

  return uploadChatAttachmentPhoto(
    scope: scope,
    parentId: parentId,
    messageId: messageId,
    localPhotoPath: path,
  );
}
