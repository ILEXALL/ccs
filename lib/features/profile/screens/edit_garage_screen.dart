import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart' show maxGaragePhotos;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/widgets/garage_gallery.dart'
    show GaragePhotoGalleryScreen;
import 'package:ccs_app/features/profile/widgets/garage_photo_image.dart'
    show garagePhotoImage;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/widgets/form_fields.dart'
    show AddSpotSection, CcsTextField;

class EditGarageScreen extends StatefulWidget {
  final GarageCar? car;

  const EditGarageScreen({super.key, this.car});

  @override
  State<EditGarageScreen> createState() => _EditGarageScreenState();
}

class _EditGarageScreenState extends State<EditGarageScreen> {
  late final TextEditingController nameController;
  late final TextEditingController descriptionController;
  late List<String> photoPaths;

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    nameController = TextEditingController(text: car?.name ?? '');
    descriptionController = TextEditingController(text: car?.description ?? '');
    photoPaths = [
      ...(car?.galleryPhotos ?? const <String>[]),
    ].take(maxGaragePhotos).toList();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> chooseCarPhoto() async {
    if (photoPaths.length >= maxGaragePhotos) {
      return;
    }

    final path = await pickPhotoFromPhone(context);

    if (!mounted || path == null) {
      return;
    }

    setState(
      () => photoPaths = [...photoPaths, path].take(maxGaragePhotos).toList(),
    );
  }

  void removeCarPhoto(int index) {
    if (index < 0 || index >= photoPaths.length) {
      return;
    }

    setState(() => photoPaths = [...photoPaths]..removeAt(index));
  }

  void makeCarPhotoCover(int index) {
    if (index <= 0 || index >= photoPaths.length) {
      return;
    }

    final nextPhotos = [...photoPaths];
    final selectedPhoto = nextPhotos.removeAt(index);
    nextPhotos.insert(0, selectedPhoto);

    setState(() => photoPaths = nextPhotos.take(maxGaragePhotos).toList());
  }

  void saveCar() {
    final cleanPhotos = photoPaths
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .take(maxGaragePhotos)
        .toList();

    Navigator.pop(
      context,
      GarageCar(
        name: nameController.text.trim().isEmpty
            ? 'Untitled car'
            : nameController.text.trim(),
        description: descriptionController.text.trim().isEmpty
            ? 'Car profile.'
            : descriptionController.text.trim(),
        photoPath: cleanPhotos.isEmpty ? null : cleanPhotos.first,
        photoPaths: cleanPhotos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.car != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(isEditing ? 'Edit Garage' : 'Add Car'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          AddSpotSection(
            title: 'Car photos',
            children: [
              _GaragePhotoPickerField(
                photoPaths: photoPaths,
                onAddPhoto: chooseCarPhoto,
                onRemovePhoto: removeCarPhoto,
                onMakeCover: makeCarPhotoCover,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AddSpotSection(
            title: 'Car info',
            children: [
              CcsTextField(
                controller: nameController,
                label: 'Car name',
                hint: 'Car name',
                icon: Icons.directions_car,
              ),
              CcsTextField(
                controller: descriptionController,
                label: 'Description',
                hint: 'Tell people about your car, build, setup, and plans',
                icon: Icons.notes,
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: saveCar,
              icon: const Icon(Icons.check),
              label: CcsText(isEditing ? 'Save Garage' : 'Add Car'),
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
  }
}

class _GaragePhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final ValueChanged<int> onMakeCover;

  const _GaragePhotoPickerField({
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onMakeCover,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxGaragePhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photoPaths.isNotEmpty
                    ? blue.withValues(alpha: 0.7)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    canAddMore ? Icons.add_photo_alternate : Icons.check,
                    color: blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CcsText(
                        photoPaths.isEmpty
                            ? 'Upload photos'
                            : '${photoPaths.length}/$maxGaragePhotos photos selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      CcsText(
                        canAddMore
                            ? 'Add up to 4 car photos. Tap Set to choose the cover.'
                            : 'Maximum 4 photos selected. Tap Set to choose the cover.',
                        style: const TextStyle(
                          color: Colors.white54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  canAddMore ? Icons.chevron_right : Icons.lock,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          appPageRoute(
                            builder: (_) => GaragePhotoGalleryScreen(
                              car: GarageCar(
                                name: 'Garage photos',
                                description: '',
                                photoPaths: photoPaths,
                              ),
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: garagePhotoImage(
                          photoPaths[index],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: InkWell(
                        onTap: index == 0 ? null : () => onMakeCover(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: index == 0
                                ? blue.withValues(alpha: 0.9)
                                : Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: index == 0
                                ? null
                                : Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                index == 0 ? Icons.star : Icons.star_border,
                                color: Colors.white,
                                size: 11,
                              ),
                              const SizedBox(width: 3),
                              CcsText(
                                index == 0 ? 'Cover' : 'Set',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => onRemovePhoto(index),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
