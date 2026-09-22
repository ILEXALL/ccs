import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart'
    show r2JpegQuality, r2SpotPhotoMaxLongSide;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show createForumTopic, maxForumTopicPhotos;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show
        forumCategoryById,
        forumCategoryConfigs,
        forumCategoryIdFromFirebase,
        forumCategoryTitle;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart'
    show spotPhotoImage;
import 'package:ccs_app/shared/media/entity_photos.dart'
    show uploadForumTopicAvatarPhoto;
import 'package:ccs_app/shared/media/media_upload.dart'
    show safeR2Path, uploadImageToR2;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;

class NewForumTopicPage extends StatefulWidget {
  final String? initialCategory;

  const NewForumTopicPage({super.key, this.initialCategory});

  @override
  State<NewForumTopicPage> createState() => _NewForumTopicPageState();
}

class _NewForumTopicPageState extends State<NewForumTopicPage>
    with LanguageReactiveState {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  late String categoryId;
  String? localAvatarPath;
  final List<String> photoPaths = [];
  bool isPickingPhoto = false;
  bool isSaving = false;
  bool isPickingAvatar = false;

  @override
  void initState() {
    super.initState();
    categoryId = forumCategoryIdFromFirebase(
      widget.initialCategory ?? forumCategoryConfigs.first.id,
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickTopicAvatar() async {
    if (isPickingAvatar || isPickingPhoto || isSaving) {
      return;
    }

    setState(() => isPickingAvatar = true);
    try {
      final path = await pickPhotoFromPhone(context, cropPhoto: false);
      if (mounted && path != null && path.trim().isNotEmpty) {
        setState(() => localAvatarPath = path);
      }
    } finally {
      if (mounted) {
        setState(() => isPickingAvatar = false);
      }
    }
  }

  Future<void> pickTopicPhoto() async {
    if (isSaving ||
        isPickingPhoto ||
        isPickingAvatar ||
        photoPaths.length >= maxForumTopicPhotos) {
      return;
    }
    setState(() => isPickingPhoto = true);
    try {
      final path = await pickPhotoFromPhone(context, cropPhoto: false);
      if (mounted &&
          path != null &&
          path.trim().isNotEmpty &&
          !photoPaths.contains(path)) {
        setState(() => photoPaths.add(path));
      }
    } finally {
      if (mounted) setState(() => isPickingPhoto = false);
    }
  }

  Widget photoPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CcsText(
        trText('Topic photos (optional, up to 4)'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var index = 0; index < photoPaths.length; index++)
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: spotPhotoImage('local:${photoPaths[index]}'),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: trText('Remove photo'),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: isSaving || isPickingPhoto
                          ? null
                          : () => setState(() => photoPaths.removeAt(index)),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photoPaths.length < maxForumTopicPhotos)
            SizedBox(
              width: 88,
              height: 88,
              child: OutlinedButton(
                onPressed: isSaving || isPickingPhoto || isPickingAvatar
                    ? null
                    : pickTopicPhoto,
                child: Icon(
                  isPickingPhoto
                      ? Icons.hourglass_top
                      : Icons.add_photo_alternate_outlined,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      CcsText(
        '${photoPaths.length}/$maxForumTopicPhotos',
        style: const TextStyle(color: Colors.white54),
      ),
    ],
  );

  void showRequiredFieldMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> createTopic() async {
    if (isSaving || isPickingPhoto || isPickingAvatar) return;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final avatarPath = localAvatarPath;

    if (firebaseUser == null) {
      showRequiredFieldMessage(trText('Log in before creating a forum topic.'));
      return;
    }

    if (avatarPath == null || avatarPath.trim().isEmpty) {
      showRequiredFieldMessage(trText('Topic avatar is required.'));
      return;
    }

    if (title.isEmpty) {
      showRequiredFieldMessage(trText('Topic name is required.'));
      return;
    }

    if (description.isEmpty) {
      showRequiredFieldMessage(trText('Topic description is required.'));
      return;
    }

    if (isSaving) {
      return;
    }

    setState(() => isSaving = true);

    try {
      final avatarUrl = await uploadForumTopicAvatarPhoto(
        userId: firebaseUser.uid,
        localPhotoPath: avatarPath,
      );

      final photoUrls = <String>[];
      final batchId = DateTime.now().microsecondsSinceEpoch;
      for (var index = 0; index < photoPaths.length; index++) {
        photoUrls.add(
          await uploadImageToR2(
            r2Path:
                'users/${safeR2Path(firebaseUser.uid)}/forum_topic_photos/${batchId}_$index.jpg',
            localPhotoPath: photoPaths[index],
            maxLongSide: r2SpotPhotoMaxLongSide,
            quality: r2JpegQuality,
          ),
        );
      }
      final topicStatus = await createForumTopic(
        title: title,
        category: categoryId,
        description: description,
        avatarUrl: avatarUrl,
        photoUrls: photoUrls,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: blue,
            content: CcsText(
              topicStatus == 'approved'
                  ? trText('Topic created')
                  : trText('Topic sent for review'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              '${trText('Could not create topic')}: $error',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  InputDecoration inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF101722),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF253246)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF253246)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: blue),
      ),
    );
  }

  Widget avatarPicker() {
    return InkWell(
      onTap: pickTopicAvatar,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 164,
        decoration: BoxDecoration(
          color: const Color(0xFF101722),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: localAvatarPath == null ? const Color(0xFF253246) : blue,
          ),
        ),
        child: localAvatarPath != null
            ? Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: Image.file(
                        File(localAvatarPath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          CcsText(
                            trText('Change avatar'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPickingAvatar
                          ? Icons.hourglass_top
                          : Icons.add_photo_alternate_outlined,
                      color: blue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CcsText(
                    trText('Upload topic avatar'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CcsText(
                    trText('Required to create a topic'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: CcsText(trText('New topic')),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          CcsText(
            trText('Create forum topic'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          CcsText(
            trText(
              'Add an avatar, name, and description. You can also attach up to 4 photos.',
            ),
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 18),
          avatarPicker(),
          const SizedBox(height: 14),
          TextField(
            controller: titleController,
            style: const TextStyle(color: Colors.white),
            decoration: inputDecoration(trText('Topic name')),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF101722),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF253246)),
            ),
            child: Row(
              children: [
                Icon(forumCategoryById(categoryId).icon, color: blue, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: CcsText(
                    forumCategoryTitle(categoryId),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: descriptionController,
            minLines: 4,
            maxLines: 7,
            style: const TextStyle(color: Colors.white),
            decoration: inputDecoration(trText('Description')),
          ),
          const SizedBox(height: 18),
          photoPicker(),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: isSaving || isPickingPhoto || isPickingAvatar
                  ? null
                  : createTopic,
              icon: Icon(isSaving ? Icons.hourglass_top : Icons.add),
              label: CcsText(
                isSaving ? trText('Creating topic...') : trText('Create topic'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: blue.withValues(alpha: 0.45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
