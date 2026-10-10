import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart'
    show SpotPhotoPlaceholder, spotPhotoImage, spotPhotoSources;

class SpotPhotoCarousel extends StatefulWidget {
  final CarSpot? spot;
  final List<String>? photoSources;
  final double height;
  final bool containWithBlur;

  const SpotPhotoCarousel({
    super.key,
    required this.spot,
    required this.height,
    this.containWithBlur = false,
  }) : photoSources = null;

  const SpotPhotoCarousel.photos({
    super.key,
    required List<String> sources,
    required this.height,
    this.containWithBlur = false,
  }) : spot = null,
       photoSources = sources;

  @override
  State<SpotPhotoCarousel> createState() => _SpotPhotoCarouselState();
}

class _SpotPhotoCarouselState extends State<SpotPhotoCarousel> {
  late final PageController controller;
  int currentIndex = 0;

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
    Navigator.push(
      context,
      appPageRoute(
        builder: (_) => SpotPhotoGalleryScreen.photos(
          sources: widget.photoSources ?? spotPhotoSources(widget.spot!),
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.photoSources ?? spotPhotoSources(widget.spot!);

    if (sources.isEmpty) {
      return SpotPhotoPlaceholder(height: widget.height);
    }

    if (currentIndex >= sources.length) {
      currentIndex = sources.length - 1;
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: controller,
            itemCount: sources.length,
            onPageChanged: (index) => setState(() => currentIndex = index),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => openGallery(index),
                child: widget.containWithBlur
                    ? EventPosterImage(source: sources[index])
                    : spotPhotoImage(
                        sources[index],
                        width: double.infinity,
                        height: widget.height,
                        fit: BoxFit.cover,
                      ),
              );
            },
          ),
          if (sources.length > 1)
            Positioned(
              top: 14,
              right: 14,
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
                  '${currentIndex + 1}/${sources.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          if (sources.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < sources.length; index++)
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
        ],
      ),
    );
  }
}

/// Preserve the complete poster; a blurred copy fills unused aspect-ratio space.
class EventPosterImage extends StatelessWidget {
  const EventPosterImage({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 18,
            sigmaY: 18,
            tileMode: TileMode.clamp,
          ),
          child: spotPhotoImage(
            source,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        const ColoredBox(color: Color(0x44000000)),
        spotPhotoImage(
          source,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
        ),
      ],
    ),
  );
}

class SpotPhotoGalleryScreen extends StatefulWidget {
  final CarSpot? spot;
  final List<String>? photoSources;
  final int initialIndex;

  const SpotPhotoGalleryScreen({
    super.key,
    required this.spot,
    required this.initialIndex,
  }) : photoSources = null;

  const SpotPhotoGalleryScreen.photos({
    super.key,
    required List<String> sources,
    required this.initialIndex,
  }) : spot = null,
       photoSources = sources;

  @override
  State<SpotPhotoGalleryScreen> createState() => _SpotPhotoGalleryScreenState();
}

class _SpotPhotoGalleryScreenState extends State<SpotPhotoGalleryScreen> {
  late final List<String> sources;
  late final PageController controller;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    sources = widget.photoSources ?? spotPhotoSources(widget.spot!);
    currentIndex =
        widget.initialIndex >= 0 && widget.initialIndex < sources.length
        ? widget.initialIndex
        : 0;
    controller = PageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (sources.isEmpty)
            const Center(
              child: Icon(Icons.directions_car, color: blue, size: 44),
            )
          else
            PageView.builder(
              controller: controller,
              itemCount: sources.length,
              onPageChanged: (index) => setState(() => currentIndex = index),
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: spotPhotoImage(
                      sources[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  if (sources.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: CcsText(
                        '${currentIndex + 1}/${sources.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
