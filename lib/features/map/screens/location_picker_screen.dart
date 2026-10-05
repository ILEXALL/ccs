import 'package:ccs_app/features/map/data/globe_context_spots.dart';
import 'package:ccs_app/features/map/data/map_overview.dart'
    show currentMapStartLocation;
import 'package:ccs_app/features/map/data/map_overview.dart'
    show loadedSpotsMapCenter;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show maintenanceModeConfig;
import 'package:ccs_app/core/config/app_config.dart' show maxSpotGalleryPhotos;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'globe_map_screen.dart';
import 'package:ccs_app/features/spots/data/spot_regions.dart'
    show
        SpotCountryOutline,
        SpotLocationRegion,
        loadSpotCountryOutlines,
        lookupSpotLocationRegion,
        spotCountryIsSupported;

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;

  final bool restrictSpotRegions;

  const LocationPickerScreen({
    super.key,
    this.initialLocation,
    this.restrictSpotRegions = false,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with LanguageReactiveState {
  LatLng defaultCenter = const LatLng(20, 0);
  bool centerLoading = true;
  double defaultZoom = 13.0;

  LatLng? pickedLocation;
  SpotLocationRegion? pickedRegion;
  bool checkingRegion = false;
  int lookupRevision = 0;
  List<SpotCountryOutline> outlines = const [];

  void regionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> selectPin(LatLng point) async {
    final revision = ++lookupRevision;
    setState(() {
      pickedLocation = point;
      pickedRegion = null;
      checkingRegion = widget.restrictSpotRegions;
    });
    if (!widget.restrictSpotRegions) return;
    final region = await lookupSpotLocationRegion(point);
    if (!mounted || revision != lookupRevision) return;
    setState(() {
      pickedRegion = region;
      checkingRegion = false;
    });
    if (!region.allowed) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(trText(region.warning)),
        ),
      );
    }
  }

  Future<void> loadOutlines() async {
    try {
      final loaded = await loadSpotCountryOutlines();
      if (mounted) setState(() => outlines = loaded);
    } catch (_) {
      /* Pin verification still works if the visual asset fails. */
    }
  }

  @override
  void initState() {
    super.initState();
    pickedLocation = widget.initialLocation;
    unawaited(loadProfileCenter());
    maintenanceModeConfig.addListener(regionsChanged);
    if (widget.restrictSpotRegions) {
      unawaited(loadOutlines());
      if (pickedLocation != null) unawaited(selectPin(pickedLocation!));
    }
  }

  Future<void> loadProfileCenter() async {
    if (widget.initialLocation == null) {
      final location = await currentMapStartLocation();
      if (!mounted) return;
      defaultCenter = location ?? loadedSpotsMapCenter();
      defaultZoom = location == null ? 3 : 13;
    }
    if (mounted) setState(() => centerLoading = false);
  }

  @override
  void dispose() {
    maintenanceModeConfig.removeListener(regionsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation =
        pickedLocation != null &&
        (!widget.restrictSpotRegions ||
            (!checkingRegion && pickedRegion?.allowed == true));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText('Choose Location')),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: SafeArea(
        top: false,
        child: centerLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  GlobeMapScreen(
                    showControls: false,
                    isSharing: false,
                    sharingBusy: false,
                    onShareChanged: (_) async {},
                    onFilter: () async {},
                    onAddReport: () async {},
                    onLocate: () async {},
                    cardBuilder: (_, _, _) => null,
                    onPick: (lat, lng) =>
                        unawaited(selectPin(LatLng(lat, lng))),
                    readFeatures: () => {
                      'type': 'FeatureCollection',
                      'camera': {
                        'revision': 0,
                        'center': [
                          (widget.initialLocation ?? defaultCenter).longitude,
                          (widget.initialLocation ?? defaultCenter).latitude,
                        ],
                        'zoom': defaultZoom,
                      },
                      'features': [
                        ...globeContextSpots(),
                        if (pickedLocation != null)
                          {
                            'type': 'Feature',
                            'geometry': {
                              'type': 'Point',
                              'coordinates': [
                                pickedLocation!.longitude,
                                pickedLocation!.latitude,
                              ],
                            },
                            'properties': {
                              'kind': 'pin',
                              'icon': checkingRegion
                                  ? 'ccs-pin-amber'
                                  : widget.restrictSpotRegions &&
                                        pickedRegion?.allowed != true
                                  ? 'ccs-pin-red'
                                  : 'ccs-pin-blue',
                              'label': 'Selected location',
                              'color': checkingRegion
                                  ? '#ffab40'
                                  : widget.restrictSpotRegions &&
                                        pickedRegion?.allowed != true
                                  ? '#ff5252'
                                  : '#008dff',
                            },
                          },
                        if (widget.restrictSpotRegions)
                          for (final outline in outlines)
                            if (!spotCountryIsSupported(outline.code))
                              {
                                'type': 'Feature',
                                'geometry': {
                                  'type': 'Polygon',
                                  'coordinates': [
                                    for (final ring in outline.rings)
                                      [
                                        for (final p in ring)
                                          [p.longitude, p.latitude],
                                      ],
                                  ],
                                },
                                'properties': {'kind': 'restricted'},
                              },
                      ],
                    },
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app, color: blue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CcsText(
                              trText(
                                widget.restrictSpotRegions
                                    ? 'Tap to place a pin. Red regions are unsupported. Borders are approximate.'
                                    : 'Tap the map where this car spot should be placed.',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: panelGlass,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.36),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                hasLocation ? Icons.check_circle : Icons.place,
                                color: hasLocation ? blue : Colors.white54,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: CcsText(
                                  trText(
                                    checkingRegion
                                        ? 'Checking region...'
                                        : pickedRegion != null &&
                                              !pickedRegion!.allowed
                                        ? pickedRegion!.warning
                                        : hasLocation
                                        ? 'Location selected'
                                        : 'No location selected yet',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 48,
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: hasLocation
                                  ? () => Navigator.pop(context, pickedLocation)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blue,
                                disabledBackgroundColor: Colors.white12,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white38,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: CcsText(
                                trText('Use this Location'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class SpotLocationPicker extends StatelessWidget {
  final bool hasLocation;
  final bool isBusy;
  final String statusText;
  final VoidCallback onMapTap;
  final VoidCallback onAddressTap;
  final VoidCallback onCurrentTap;

  const SpotLocationPicker({
    super.key,
    required this.hasLocation,
    required this.isBusy,
    required this.statusText,
    required this.onMapTap,
    required this.onAddressTap,
    required this.onCurrentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLocation ? blue.withValues(alpha: 0.7) : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  hasLocation ? Icons.check_circle : Icons.location_on,
                  color: blue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      trText('Location'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    CcsText(
                      trText(statusText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SpotLocationActionButton(
                  icon: Icons.map,
                  label: 'Map',
                  onTap: onMapTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SpotLocationActionButton(
                  icon: Icons.search,
                  label: 'Address',
                  onTap: onAddressTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SpotLocationActionButton(
                  icon: Icons.my_location,
                  label: 'GPS',
                  onTap: onCurrentTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotLocationActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SpotLocationActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: blue, size: 17),
            const SizedBox(width: 5),
            Flexible(
              child: CcsText(
                trText(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpotPhotoPickerField extends StatelessWidget {
  final List<String> photoPaths;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const SpotPhotoPickerField({
    super.key,
    required this.photoPaths,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final canAddMore = photoPaths.length < maxSpotGalleryPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canAddMore ? onAddPhoto : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: photoPaths.isNotEmpty
                    ? blue.withValues(alpha: 0.7)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
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
                        trText(
                          photoPaths.isEmpty
                              ? 'Upload photos'
                              : '${photoPaths.length}/$maxSpotGalleryPhotos photos selected',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      CcsText(
                        trText(
                          canAddMore
                              ? 'Add up to 4 photos. First one is the cover.'
                              : 'Maximum 4 photos selected.',
                        ),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.2,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < photoPaths.length; index++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(photoPaths[index]),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) {
                          return Container(
                            width: 72,
                            height: 72,
                            color: Colors.white.withValues(alpha: 0.06),
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.white38,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? blue.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: CcsText(
                          index == 0 ? trText('Cover') : '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
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
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
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
