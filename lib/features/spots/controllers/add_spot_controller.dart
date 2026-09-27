import 'package:ccs_app/features/spots/data/group_spot_creation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show
        maxSpotGalleryPhotos,
        maxTemporarySpotDuration,
        minimumPermanentSpotDistanceMeters;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show
        FirestoreDebugDocumentReferenceExtension,
        FirestoreDebugWriteBatchExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show distanceBetweenLatLngMeters, safeLatLng, safeLatLngFromPosition;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show createTemporarySpotForumTopic;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show memberSpotGroups;
import 'package:ccs_app/features/events/data/event_reminders.dart'
    show notifyAllUsersIfTemporarySpotIsToday;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show userLocationLookupTimeout;
import 'package:ccs_app/features/map/screens/location_picker_screen.dart'
    show LocationPickerScreen;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserRegionIsRestricted;
import 'package:ccs_app/features/notifications/data/event_notifications.dart'
    show createMeetSpotNotificationsForNearbyUsers;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show createAdminSpotReviewNotification;
import 'package:ccs_app/features/notifications/data/spot_notifications.dart'
    show createNewSpotNotificationForUsers, sendNewSpotPushToEligibleUsers;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show syncXpWithServer;
import 'package:ccs_app/features/spots/data/creation_guard.dart'
    show findNearbySpotBlockingPermanentSpotCreation;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show isSelectableSpotCountry;
import 'package:ccs_app/features/spots/data/spot_regions.dart'
    show
        lookupSpotLocationRegion,
        spotCountryIsSupported,
        unknownSpotRegionMessage;
import 'package:ccs_app/features/spots/data/spot_serialization.dart'
    show spotToFirestoreData;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show upsertSpotIntoLocalImmediateCache;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show defaultServiceOpeningHours;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategoryOptions, spotCategorySupportsContacts;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/shared/media/entity_photos.dart' show uploadSpotPhoto;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/countries.dart'
    show spotCountryFromCityCountry;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/widgets/region_unavailable_dialog.dart'
    show showRegionFeatureUnavailableDialog;
import 'package:ccs_app/features/spots/controllers/add_spot_view_state.dart';

/// Coordinates actions and data loading for AddSpotScreen.
class AddSpotController implements AddSpotControllerActions {
  final AddSpotViewState host;
  AddSpotController(this.host);

  @override
  List<String> get categoryOptions => host.widget.eventMode
      ? spotCategoryOptions
            .where(
              (category) => !const {
                'Store',
                'Photo',
                'Service',
                'Detailing',
                'Wash',
                'Activity',
                'Food',
                'Scrap',
              }.contains(category),
            )
            .toList()
      : spotCategoryOptions;

  @override
  void groupMembershipChanged() {
    if (!host.mounted) return;
    // A sync restart or connection error can temporarily empty memberships.
    // Preserve the chosen audience; submission validates current membership.
    host.updateView(() {});
  }

  @override
  Future<bool> applySelectedLocation(LatLng location) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final revision = ++host.locationLookupRevision;
    host.updateView(() {
      host.selectedLocation = null;
      host.selectedRegion = null;
      host.detectedCityCountry = 'Detecting city/country...';
      host.isDetectingCityCountry = true;
    });
    final region = await lookupSpotLocationRegion(location);
    if (!(host.mounted && viewContext.mounted) ||
        revision != host.locationLookupRevision) {
      return false;
    }
    host.updateView(() {
      host.selectedRegion = region;
      host.selectedLocation = region.allowed ? location : null;
      host.detectedCityCountry = region.allowed
          ? region.cityCountry
          : region.warning;
      host.isDetectingCityCountry = false;
    });
    if (!region.allowed) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(trText(region.warning)),
        ),
      );
    }
    return region.allowed;
  }

  @override
  Future<void> chooseLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    final location = await Navigator.push<LatLng>(
      viewContext,
      appPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLocation: host.selectedLocation,
          restrictSpotRegions: true,
        ),
      ),
    );

    if (!(host.mounted && viewContext.mounted) || location == null) {
      return;
    }

    await applySelectedLocation(location);
  }

  @override
  Future<void> findExactAddress() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    final address = await showDialog<String>(
      context: viewContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(trText('Find exact address')),
          content: TextField(
            controller: host.addressController,
            autofocus: true,
            keyboardType: TextInputType.streetAddress,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: trText('Street, city, country'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: blue),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: blue),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: CcsText(trText('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                host.addressController.text.trim(),
              ),
              child: CcsText(trText('Find')),
            ),
          ],
        );
      },
    );

    if (!(host.mounted && viewContext.mounted) ||
        address == null ||
        address.trim().isEmpty) {
      return;
    }

    final previousDetectedCityCountry = host.detectedCityCountry;

    try {
      host.updateView(() {
        host.detectedCityCountry = 'Finding address...';
        host.isDetectingCityCountry = true;
      });

      final locations = await locationFromAddress(address.trim());

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (locations.isEmpty) {
        host.updateView(() {
          host.detectedCityCountry = host.selectedLocation == null
              ? 'Choose location to detect city/country'
              : previousDetectedCityCountry;
          host.isDetectingCityCountry = false;
        });

        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Address not found. Try adding city and country.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final first = locations.first;
      await applySelectedLocation(safeLatLng(first.latitude, first.longitude));
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() {
        host.detectedCityCountry = host.selectedLocation == null
            ? 'Choose location to detect city/country'
            : previousDetectedCityCountry;
        host.isDetectingCityCountry = false;
      });

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not find that address. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Future<void> useCurrentLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    if (host.isUsingCurrentLocation) {
      return;
    }

    final previousDetectedCityCountry = host.detectedCityCountry;

    host.updateView(() {
      host.isUsingCurrentLocation = true;
      host.isDetectingCityCountry = true;
      host.detectedCityCountry = 'Getting current location...';
    });

    void restoreLocationState() {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() {
        host.isUsingCurrentLocation = false;
        host.isDetectingCityCountry = false;
        host.detectedCityCountry = host.selectedLocation == null
            ? 'Choose location to detect city/country'
            : previousDetectedCityCountry;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (!serviceEnabled) {
        restoreLocationState();
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Turn on phone location to use your current position.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        restoreLocationState();
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Location permission is needed to use your current position.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: userLocationLookupTimeout,
        ),
      );

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      final location = safeLatLngFromPosition(position);
      if (location == null) {
        return;
      }

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if ((host.mounted && viewContext.mounted) && placemarks.isNotEmpty) {
          final place = placemarks.first;
          final addressParts =
              [place.street, place.subLocality, place.locality, place.country]
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList();

          if (addressParts.isNotEmpty) {
            host.addressController.text = addressParts.join(', ');
          }
        }
      } catch (_) {
        // Address text is optional. The coordinates are enough to create a spot.
      }

      final accepted = await applySelectedLocation(location);

      if (!(host.mounted && viewContext.mounted) || !accepted) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Current location selected for this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() {
        host.isDetectingCityCountry = false;
        host.detectedCityCountry = host.selectedLocation == null
            ? 'Choose location to detect city/country'
            : previousDetectedCityCountry;
      });

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not use current location. $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isUsingCurrentLocation = false);
      }
    }
  }

  @override
  Future<void> choosePhoto() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    if (host.selectedPhotoPaths.length >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Maximum 4 photos per spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(viewContext);

    if (!(host.mounted && viewContext.mounted) || path == null) {
      return;
    }

    if (host.selectedPhotoPaths.contains(path)) {
      return;
    }

    host.updateView(() => host.selectedPhotoPaths.add(path));
  }

  @override
  void removePhotoAt(int index) {
    if (index < 0 || index >= host.selectedPhotoPaths.length) {
      return;
    }

    host.updateView(() => host.selectedPhotoPaths.removeAt(index));
  }

  @override
  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue) async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final now = DateTime.now();
    final initial = initialValue ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: viewContext,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (date == null || !(host.mounted && viewContext.mounted)) {
      return null;
    }

    final time = await showTimePicker(
      context: viewContext,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (time == null) {
      return null;
    }

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Future<void> chooseTemporaryStart() async {
    final value = await pickTemporaryDateTime(host.temporaryStartsAt);

    if (!host.mounted || value == null) {
      return;
    }

    host.updateView(() {
      host.temporaryStartsAt = value;
      if (host.temporaryExpiresAt == null ||
          !host.temporaryExpiresAt!.isAfter(value) ||
          host.temporaryExpiresAt!.difference(value) >
              maxTemporarySpotDuration) {
        host.temporaryExpiresAt = value.add(const Duration(hours: 3));
      }
    });
  }

  @override
  Future<void> chooseTemporaryEnd() async {
    final fallback = host.temporaryStartsAt?.add(const Duration(hours: 3));
    final value = await pickTemporaryDateTime(
      host.temporaryExpiresAt ?? fallback,
    );

    if (!host.mounted || value == null) {
      return;
    }

    host.updateView(() => host.temporaryExpiresAt = value);
  }

  @override
  Future<void> chooseTemporaryShowOnMapAt() async {
    final fallback = host.temporaryStartsAt == null
        ? DateTime.now().add(const Duration(hours: 1))
        : DateTime(
            host.temporaryStartsAt!.year,
            host.temporaryStartsAt!.month,
            host.temporaryStartsAt!.day,
          );
    final value = await pickTemporaryDateTime(
      host.temporaryShowOnMapAt ?? fallback,
    );

    if (!host.mounted || value == null) {
      return;
    }

    host.updateView(() => host.temporaryShowOnMapAt = value);
  }

  @override
  void resetSpotFormAfterSubmit() {
    host.nameController.clear();
    host.cityController.clear();
    host.addressController.clear();
    host.descriptionController.clear();
    host.reelController.clear();
    host.phoneController.clear();
    host.instagramController.clear();
    host.emailController.clear();
    host.addedByController.text = currentUser.username;

    host.updateView(() {
      host.selectedCategory = host.widget.eventMode ? 'Meet' : 'Photo';
      host.selectedLocation = null;
      host.detectedCityCountry = 'Choose location to detect city/country';
      host.isDetectingCityCountry = false;
      host.selectedPhotoPaths.clear();
      host.verifiedOnlySpot = false;
      host.isTemporarySpot = host.widget.eventMode;
      host.groupVisibility = host.widget.privateEvent;
      host.selectedGroupIds.clear();
      host.temporaryStartsAt = null;
      host.temporaryExpiresAt = null;
      host.temporaryShowOnMapAtEnabled = false;
      host.temporaryShowOnMapAt = null;
      host.openingHours = defaultServiceOpeningHours();
      host.selectedOwner = null;
    });
  }

  @override
  Future<void> submitSpot() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    if (host.isSubmitting) {
      return;
    }

    host.updateView(() => host.isSubmitting = true);
    var committed = false;
    try {
      if (currentUserRegionIsRestricted) {
        await showRegionFeatureUnavailableDialog(viewContext);
        return;
      }

      final firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser == null) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Sign in with Google before submitting a spot.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      final cleanSpotName = host.nameController.text.trim();
      final cleanDescription = host.descriptionController.text.trim();
      final allowedSpotNamePattern = RegExp(
        r"^[A-Za-z0-9ĀāČčĒēĢģĪīĶķĻļŅņŠšŪūŽž .,'’&()\/-]+$",
      );

      if (cleanSpotName.isEmpty) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Spot name is required.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (!allowedSpotNamePattern.hasMatch(cleanSpotName)) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Spot name can use only English or Latvian letters, numbers, spaces, and simple punctuation.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (host.selectedLocation == null) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Location is required. Pin it on the map, find exact address, or use current location first.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (host.isDetectingCityCountry || host.isUsingCurrentLocation) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orangeAccent,
            content: CcsText(
              'Wait for the location address to finish loading.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (host.selectedRegion?.allowed != true) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              trText(host.selectedRegion?.warning ?? unknownSpotRegionMessage),
            ),
          ),
        );
        return;
      }

      if (cleanDescription.isEmpty) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Description is required.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (host.selectedPhotoPaths.isEmpty) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: CcsText(
              'Upload at least 1 photo before creating the spot.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        return;
      }

      if (host.isTemporarySpot) {
        final startsAt = host.temporaryStartsAt;
        final expiresAt = host.temporaryExpiresAt;

        if (startsAt == null || expiresAt == null) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Choose both start and end time for a event.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (!expiresAt.isAfter(startsAt)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'End time must be after start time.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (expiresAt.difference(startsAt) > maxTemporarySpotDuration) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Events can be active for maximum 12 hours.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (!expiresAt.isAfter(DateTime.now())) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                trText('End time must be in the future.'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }

        if (host.temporaryShowOnMapAtEnabled) {
          final showOnMapAt = host.temporaryShowOnMapAt;
          if (showOnMapAt == null) {
            ScaffoldMessenger.of(viewContext).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: CcsText(
                  trText(
                    'Choose when the event location should appear on the map.',
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            return;
          }

          if (!showOnMapAt.isBefore(expiresAt)) {
            ScaffoldMessenger.of(viewContext).showSnackBar(
              SnackBar(
                backgroundColor: Colors.redAccent,
                content: CcsText(
                  trText('Show on map time must be before the end time.'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            return;
          }
        }
      }

      final sharingGroups = host.isTemporarySpot && host.groupVisibility
          ? memberSpotGroups.value
                .where((group) => host.selectedGroupIds.contains(group.id))
                .toList()
          : <ChatThreadData>[];
      if (host.isTemporarySpot &&
          host.groupVisibility &&
          sharingGroups.isEmpty) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(content: CcsText(trText('Select at least one group.'))),
        );
        return;
      }
      if (host.isTemporarySpot &&
          host.groupVisibility &&
          sharingGroups.length != host.selectedGroupIds.length) {
        ScaffoldMessenger.of(viewContext).showSnackBar(
          SnackBar(
            content: CcsText(
              trText(
                'Some selected groups are unavailable. Check your group membership before submitting.',
              ),
            ),
          ),
        );
        return;
      }
      final location = host.selectedLocation!;
      final region = host.selectedRegion!;

      if (!host.isTemporarySpot) {
        final nearbySpot = await findNearbySpotBlockingPermanentSpotCreation(
          location,
        );

        if (!(host.mounted && viewContext.mounted) ||
            FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid) {
          return;
        }
        if (nearbySpot != null) {
          final distance = distanceBetweenLatLngMeters(
            location,
            nearbySpot.coordinates,
          );
          final distanceLabel = distance >= 1000
              ? '${(distance / 1000).toStringAsFixed(1)} km'
              : '${distance.round()} m';

          if (!(host.mounted && viewContext.mounted)) {
            return;
          }

          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Permanent spots must be at least ${minimumPermanentSpotDistanceMeters.round()} m apart. "${nearbySpot.name}" is $distanceLabel away. Events are allowed to overlap existing spots.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
          return;
        }
      }

      final categories = [host.selectedCategory];
      final supportsContacts = spotCategorySupportsContacts(
        host.selectedCategory,
      );
      final cleanDetectedCityCountry = region.cityCountry.trim();
      final cityCountry =
          isSelectableSpotCountry(
            spotCountryFromCityCountry(cleanDetectedCityCountry),
          )
          ? cleanDetectedCityCountry
          : 'Unknown location';
      final countryCode = region.countryCode!;
      if (!spotCountryIsSupported(countryCode)) return;
      final canCreateApprovedSpot =
          currentUser.role == UserRole.admin ||
          (currentUser.role == UserRole.moderator &&
              currentUser.moderatorCountryCodes.contains(countryCode));
      final owner = supportsContacts && canCreateApprovedSpot
          ? host.selectedOwner
          : null;

      final initialStatus = canCreateApprovedSpot
          ? SpotStatus.approved
          : SpotStatus.pending;
      final spotRef = spotsCollection().doc();

      var newSpot = CarSpot(
        id: spotRef.id,
        name: cleanSpotName,
        cityCountry: cityCountry,
        countryCode: countryCode,
        coordinates: location,
        description: cleanDescription,
        categories: categories,
        photoUrl: '',
        localPhotoPath: host.selectedPhotoPaths.isEmpty
            ? null
            : host.selectedPhotoPaths.first,
        reelLink: host.reelController.text.trim(),
        contactPhone: supportsContacts ? host.phoneController.text.trim() : '',
        contactInstagram: supportsContacts
            ? host.instagramController.text.trim()
            : '',
        contactEmail: supportsContacts ? host.emailController.text.trim() : '',
        openingHours: supportsContacts ? host.openingHours : const {},
        ownerUid: supportsContacts ? (owner?.uid ?? '') : '',
        ownerUsername: supportsContacts ? (owner?.username ?? '') : '',
        bestTime: 'Not reviewed',
        parking: 'Not reviewed',
        roadQuality: 'Not reviewed',
        lowCarFriendly: false,
        policeRisk: 'Not reviewed',
        traffic: 'Not reviewed',
        lighting: 'Not reviewed',
        crowd: 'Not reviewed',
        addedBy: currentUser.username,
        addedByUid: firebaseUser.uid,
        status: initialStatus,
        visibility: sharingGroups.isEmpty ? 'public' : 'group',
        sharedGroupIds: sharingGroups.map((group) => group.id).toList(),
        sharedGroups: sharingGroups
            .map(
              (group) => <String, dynamic>{
                'id': group.id,
                'name': group.name,
                'avatarUrl': group.avatarUrl.isNotEmpty
                    ? group.avatarUrl
                    : group.photoUrl,
              },
            )
            .toList(),
        isTemporary: host.isTemporarySpot,
        startsAtMillis: host.isTemporarySpot
            ? host.temporaryStartsAt!.millisecondsSinceEpoch
            : null,
        expiresAtMillis: host.isTemporarySpot
            ? host.temporaryExpiresAt!.millisecondsSinceEpoch
            : null,
        showOnMapAtMillis:
            host.isTemporarySpot && host.temporaryShowOnMapAtEnabled
            ? host.temporaryShowOnMapAt!.millisecondsSinceEpoch
            : null,
        verifiedOnly: sharingGroups.isEmpty && host.verifiedOnlySpot,
      );

      final uploadedPhotoUrls = <String>[];

      for (var index = 0; index < host.selectedPhotoPaths.length; index++) {
        final uploadedUrl = await uploadSpotPhoto(
          spotId: spotRef.id,
          localPhotoPath: host.selectedPhotoPaths[index],
          userId: firebaseUser.uid,
          photoIndex: index,
        );
        uploadedPhotoUrls.add(uploadedUrl);
      }

      newSpot = newSpot.copyWith(
        photoUrl: uploadedPhotoUrls.isEmpty ? '' : uploadedPhotoUrls.first,
        photoUrls: uploadedPhotoUrls,
      );
      if (!(host.mounted && viewContext.mounted) ||
          FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid) {
        return;
      }
      if (newSpot.isGroupSpot) {
        await createGroupSpotOnServer(newSpot);
      } else {
        final batch = FirebaseFirestore.instance.batch();
        batch.set(
          spotRef,
          spotToFirestoreData(newSpot, includeCreatedAt: true),
        );
        await batch.debugCommit();
      }
      committed = true;
      // The write is already confirmed. Do not wait for a second network
      // request (or notification fan-out) to show the creator their spot.
      if (FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid) return;
      upsertSpotIntoLocalImmediateCache(newSpot);

      if (newSpot.isTemporary && !newSpot.isGroupSpot) {
        unawaited(createTemporarySpotForumTopic(newSpot));
      }

      var savedNewSpot = newSpot;
      try {
        final savedSpot = await spotRef
            .debugGet(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
        if (savedSpot.exists) savedNewSpot = CarSpot.fromFirestore(savedSpot);
      } catch (error) {
        // The write succeeded; the live feed will reconcile server timestamps.
        debugPrint('Saved spot read-back deferred to live sync: $error');
      }
      if (FirebaseAuth.instance.currentUser?.uid != firebaseUser.uid) return;
      upsertSpotIntoLocalImmediateCache(savedNewSpot);

      if (canCreateApprovedSpot) {
        await createNewSpotNotificationForUsers(savedNewSpot);
        await notifyAllUsersIfTemporarySpotIsToday(savedNewSpot);

        await sendNewSpotPushToEligibleUsers(savedNewSpot);
      }

      if (canCreateApprovedSpot && savedNewSpot.categories.contains('Meet')) {
        await createMeetSpotNotificationsForNearbyUsers(savedNewSpot);
      }

      if (canCreateApprovedSpot) {
        unawaited(
          syncXpWithServer({'action': 'sync_spot', 'spotId': savedNewSpot.id}),
        );
      }

      if (!canCreateApprovedSpot) {
        try {
          await createAdminSpotReviewNotification(savedNewSpot);
        } catch (error, stack) {
          debugPrint('Could not create staff spot review notification: $error');
          debugPrint('$stack');
        }
      }

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      resetSpotFormAfterSubmit();

      final message = host.widget.eventMode
          ? communityText(
              en: canCreateApprovedSpot
                  ? 'Event added. It is live now.'
                  : 'Event submitted for review.',
              ru: canCreateApprovedSpot
                  ? 'Событие опубликовано.'
                  : 'Событие отправлено на проверку.',
              lv: canCreateApprovedSpot
                  ? 'Pasākums publicēts.'
                  : 'Pasākums iesniegts pārskatīšanai.',
            )
          : canCreateApprovedSpot
          ? 'Admin spot added. It is live now.'
          : 'Spot submitted for review. Admins have been notified.';

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            trText(message),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Spot submission (committed=$committed): $error\n$stack');
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (committed) resetSpotFormAfterSubmit();
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: committed ? blue : Colors.redAccent,
          content: CcsText(
            trText(
              committed
                  ? 'Spot saved successfully, but some notifications could not be sent.'
                  : 'Could not save the spot or photos. Check your connection and try again.',
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isSubmitting = false);
      }
    }
  }
}
