import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/widgets/garage_gallery.dart'
    show GaragePhotoGalleryScreen;
import 'package:ccs_app/features/profile/widgets/garage_photo_image.dart'
    show GaragePhotoFallback, garagePhotoImage;

class GarageCarPhoto extends StatefulWidget {
  final GarageCar car;

  const GarageCarPhoto({super.key, required this.car});

  @override
  State<GarageCarPhoto> createState() => _GarageCarPhotoState();
}

class _GarageCarPhotoState extends State<GarageCarPhoto> {
  final PageController controller = PageController();
  int currentIndex = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    if (photos.isEmpty) {
      return const GaragePhotoFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              appPageRoute(
                builder: (_) => GaragePhotoGalleryScreen(
                  car: widget.car,
                  initialIndex: currentIndex,
                ),
              ),
            );
          },
          child: PageView.builder(
            controller: controller,
            itemCount: photos.length,
            onPageChanged: (index) => setState(() => currentIndex = index),
            itemBuilder: (context, index) {
              return garagePhotoImage(photos[index], fit: BoxFit.cover);
            },
          ),
        ),
        if (photos.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: CcsText(
                '${currentIndex + 1}/${photos.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
