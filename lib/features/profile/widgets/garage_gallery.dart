import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/config/app_config.dart'
    show garagePhotoAspectRatio;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/profile/models/garage_car.dart' show GarageCar;
import 'package:ccs_app/features/profile/widgets/garage_photo_image.dart'
    show GaragePhotoFallback, garagePhotoImage;

class _GarageGalleryHeader extends StatefulWidget {
  final GarageCar car;

  const _GarageGalleryHeader({required this.car});

  @override
  State<_GarageGalleryHeader> createState() => _GarageGalleryHeaderState();
}

class _GarageGalleryHeaderState extends State<_GarageGalleryHeader> {
  late final PageController controller;
  int currentIndex = 0;

  List<String> get photos => widget.car.galleryPhotos;

  @override
  void initState() {
    super.initState();
    controller = PageController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void openGallery(int index) {
    if (photos.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      appPageRoute(
        builder: (_) =>
            GaragePhotoGalleryScreen(car: widget.car, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentIndex >= photos.length) {
      currentIndex = photos.isEmpty ? 0 : photos.length - 1;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: AspectRatio(
        aspectRatio: garagePhotoAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              const GaragePhotoFallback()
            else
              PageView.builder(
                controller: controller,
                itemCount: photos.length,
                onPageChanged: (index) => setState(() => currentIndex = index),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => openGallery(index),
                    child: garagePhotoImage(
                      photos[index],
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                top: 14,
                right: 14,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
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
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 26,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 270),
                    child: CcsText(
                      widget.car.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (photos.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < photos.length; index++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: currentIndex == index ? 18 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: currentIndex == index
                                  ? blue
                                  : Colors.white.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GaragePhotoGalleryScreen extends StatefulWidget {
  final GarageCar car;
  final int initialIndex;

  const GaragePhotoGalleryScreen({
    super.key,
    required this.car,
    required this.initialIndex,
  });

  @override
  State<GaragePhotoGalleryScreen> createState() =>
      _GaragePhotoGalleryScreenState();
}

class _GaragePhotoGalleryScreenState extends State<GaragePhotoGalleryScreen> {
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex.clamp(
      0,
      widget.car.galleryPhotos.length - 1,
    );
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.car.galleryPhotos;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: CcsText(
          photos.isEmpty
              ? widget.car.name
              : '${widget.car.name}  ${currentIndex + 1}/${photos.length}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: photos.isEmpty
          ? const Center(child: GaragePhotoFallback())
          : PageView.builder(
              controller: controller,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: garagePhotoImage(
                      photos[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class GarageCard extends StatelessWidget {
  final GarageCar car;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const GarageCard({super.key, required this.car, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GarageGalleryHeader(car: car),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CcsText(
                  car.description,
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                ),
                if (onEdit != null || onDelete != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (onEdit != null)
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const CcsText('Edit Garage'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (onEdit != null && onDelete != null)
                        const SizedBox(width: 10),
                      if (onDelete != null)
                        SizedBox(
                          width: 48,
                          height: 44,
                          child: IconButton.filled(
                            tooltip: 'Delete vehicle',
                            onPressed: onDelete,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyGarageCard extends StatelessWidget {
  final VoidCallback onAdd;

  const EmptyGarageCard({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panelGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car, color: blue, size: 30),
          ),
          const SizedBox(height: 14),
          CcsText(
            trText('No cars in garage'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          CcsText(
            trText('Add your first car to show it on your profile.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: CcsText(trText('Add Car')),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
