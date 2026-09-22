import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/core/config/app_config.dart'
    show maxSpotGalleryPhotos, maxTemporarySpotDuration;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/location/coordinates.dart'
    show detectCityCountryForCoordinates, safeLatLng, safeLatLngFromPosition;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/map/data/live_location_config.dart'
    show userLocationLookupTimeout;
import 'package:ccs_app/features/map/screens/location_picker_screen.dart'
    show LocationPickerScreen;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/moderation/widgets/spot_actions.dart'
    show showAdminActionError;
import 'package:ccs_app/features/notifications/data/moderation_notifications.dart'
    show createAdminSpotEditReviewNotification;
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart'
    show reviewSpots, savedSpots, submittedSpots;
import 'package:ccs_app/features/spots/data/spot_sync.dart'
    show upsertSpotIntoLocalImmediateCache;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show openingHoursToFirebase;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show spotCategorySupportsContacts;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart'
    show primarySpotCategory;
import 'package:ccs_app/shared/media/entity_photos.dart' show uploadSpotPhoto;
import 'package:ccs_app/shared/media/photo_picker.dart' show pickPhotoFromPhone;
import 'package:ccs_app/shared/models/countries.dart'
    show countryIsoCode, spotCountryFromCityCountry;
import 'package:ccs_app/shared/models/user_role.dart'
    show UserRole, userRoleIsStaff;
import 'package:ccs_app/features/moderation/controllers/admin_edit_spot_view_state.dart';

/// Coordinates actions and data loading for AdminEditSpotScreen.
class AdminEditSpotController implements AdminEditSpotControllerActions {
  final AdminEditSpotViewState host;
  AdminEditSpotController(this.host);

  @override
  int get totalPhotoCount =>
      host.existingPhotoUrls.length + host.newPhotoPaths.length;

  @override
  Future<void> addPhoto() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (totalPhotoCount >= maxSpotGalleryPhotos) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Maximum 4 spot photos.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    final path = await pickPhotoFromPhone(viewContext);
    if (!(host.mounted && viewContext.mounted) ||
        path == null ||
        path.trim().isEmpty) {
      return;
    }

    if (host.newPhotoPaths.contains(path)) {
      return;
    }

    host.updateView(() => host.newPhotoPaths.add(path));
  }

  @override
  void removeExistingPhotoAt(int index) {
    if (index < 0 || index >= host.existingPhotoUrls.length) {
      return;
    }

    host.updateView(() => host.existingPhotoUrls.removeAt(index));
  }

  @override
  void removeNewPhotoAt(int index) {
    if (index < 0 || index >= host.newPhotoPaths.length) {
      return;
    }

    host.updateView(() => host.newPhotoPaths.removeAt(index));
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
  Future<void> applyEditedLocation(LatLng location) async {
    host.updateView(() => host.isUpdatingEditLocation = true);

    try {
      final cityCountry = await detectCityCountryForCoordinates(location);

      if (!host.mounted) {
        return;
      }

      host.updateView(() {
        host.latController.text = location.latitude.toStringAsFixed(6);
        host.lngController.text = location.longitude.toStringAsFixed(6);
        host.cityController.text = cityCountry.trim().isEmpty
            ? host.cityController.text
            : cityCountry.trim();
      });
    } finally {
      if (host.mounted) {
        host.updateView(() => host.isUpdatingEditLocation = false);
      }
    }
  }

  @override
  Future<void> chooseEditedLocationOnMap() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    final currentLat = double.tryParse(
      host.latController.text.trim().replaceAll(',', '.'),
    );
    final currentLng = double.tryParse(
      host.lngController.text.trim().replaceAll(',', '.'),
    );
    final initialLocation = currentLat == null || currentLng == null
        ? host.widget.spot.coordinates
        : safeLatLng(currentLat, currentLng);

    final location = await Navigator.push<LatLng>(
      viewContext,
      appPageRoute(
        builder: (_) => LocationPickerScreen(initialLocation: initialLocation),
      ),
    );

    if (!(host.mounted && viewContext.mounted) || location == null) {
      return;
    }

    await applyEditedLocation(location);
  }

  @override
  Future<void> chooseEditedLocationByAddress() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    final addressController = TextEditingController(
      text: host.cityController.text.trim(),
    );

    final address = await showDialog<String>(
      context: viewContext,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panelGlass,
          title: CcsText(trText('Find exact address')),
          content: TextField(
            controller: addressController,
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
              onPressed: () =>
                  Navigator.pop(dialogContext, addressController.text.trim()),
              child: CcsText(trText('Find')),
            ),
          ],
        );
      },
    );

    addressController.dispose();

    if (!(host.mounted && viewContext.mounted) ||
        address == null ||
        address.trim().isEmpty) {
      return;
    }

    try {
      host.updateView(() => host.isUpdatingEditLocation = true);
      final locations = await locationFromAddress(address.trim());

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (locations.isEmpty) {
        host.updateView(() => host.isUpdatingEditLocation = false);
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
      await applyEditedLocation(safeLatLng(first.latitude, first.longitude));
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() => host.isUpdatingEditLocation = false);
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
  Future<void> chooseEditedCurrentLocation() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    FocusScope.of(viewContext).unfocus();

    if (host.isUpdatingEditLocation) {
      return;
    }

    try {
      host.updateView(() => host.isUpdatingEditLocation = true);

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      if (!serviceEnabled) {
        host.updateView(() => host.isUpdatingEditLocation = false);
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
        host.updateView(() => host.isUpdatingEditLocation = false);
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
        host.updateView(() => host.isUpdatingEditLocation = false);
        return;
      }

      await applyEditedLocation(location);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      host.updateView(() => host.isUpdatingEditLocation = false);
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not get current location. $error',
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
  Future<void> saveSpot() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isOwner = host.widget.spot.addedByUid == firebaseUser?.uid;
    final isStaff = userRoleIsStaff(currentUser.role);
    if (firebaseUser == null || (!isOwner && !isStaff)) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Only the assigned owner or an admin can edit this spot.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }
    if (currentUser.role == UserRole.moderator &&
        !currentUserCanModerateSpot(host.widget.spot)) {
      showAdminActionError(
        viewContext,
        message: trText('This spot is outside your assigned countries'),
        error: 'regional-moderator-scope',
      );
      return;
    }

    final cleanName = host.nameController.text.trim();
    final cleanCity = host.cityController.text.trim();
    final cleanDescription = host.descriptionController.text.trim();
    final editedLatitude = double.tryParse(
      host.latController.text.trim().replaceAll(',', '.'),
    );
    final editedLongitude = double.tryParse(
      host.lngController.text.trim().replaceAll(',', '.'),
    );
    final cleanReel = host.reelController.text.trim();
    final cleanPhone = host.phoneController.text.trim();
    final cleanInstagram = host.instagramController.text.trim();
    final cleanEmail = host.emailController.text.trim();
    final supportsContacts = spotCategorySupportsContacts(
      host.selectedCategory,
    );
    final owner = supportsContacts ? host.selectedOwner : null;

    if (host.widget.spot.id.trim().isEmpty) {
      showAdminActionError(
        viewContext,
        message: 'Could not save spot',
        error: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'missing-spot-id',
        ),
      );
      return;
    }

    if (editedLatitude == null ||
        editedLongitude == null ||
        editedLatitude < -90 ||
        editedLatitude > 90 ||
        editedLongitude < -180 ||
        editedLongitude > 180) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Enter valid latitude and longitude.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (cleanName.isEmpty || cleanDescription.isEmpty) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Spot name and description are required.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
              'Event end time must be after start time.',
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
              'Event can be active for 12 hours maximum.',
              style: TextStyle(
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
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Choose when the event location should appear on the map.',
                style: TextStyle(
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
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                'Show on map time must be before the end time.',
                style: TextStyle(
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

    host.updateView(() => host.isSaving = true);

    try {
      final finalPhotoUrls = <String>[...host.existingPhotoUrls];

      for (final localPhotoPath in host.newPhotoPaths) {
        final uploadIndex = finalPhotoUrls.length;
        final uploadedUrl = await uploadSpotPhoto(
          spotId: host.widget.spot.id,
          localPhotoPath: localPhotoPath,
          userId: firebaseUser.uid,
          photoIndex: uploadIndex,
        );
        finalPhotoUrls.add(uploadedUrl);
      }

      final updatedCityCountry = cleanCity.isEmpty
          ? host.widget.spot.cityCountry
          : cleanCity;
      final updatedCountryCode =
          countryIsoCode(spotCountryFromCityCountry(updatedCityCountry)) ??
          host.widget.spot.effectiveCountryCode;
      if (currentUser.role == UserRole.moderator &&
          updatedCountryCode != host.widget.spot.effectiveCountryCode) {
        if ((host.mounted && viewContext.mounted)) {
          ScaffoldMessenger.of(viewContext).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: CcsText(
                trText(
                  'Regional moderators cannot move spots to another country.',
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return;
      }

      final updatedSpot = host.widget.spot.copyWith(
        name: cleanName,
        cityCountry: updatedCityCountry,
        countryCode: updatedCountryCode,
        description: cleanDescription,
        coordinates: safeLatLng(editedLatitude, editedLongitude),
        categories: [host.selectedCategory],
        reelLink: cleanReel,
        contactPhone: supportsContacts ? cleanPhone : '',
        contactInstagram: supportsContacts ? cleanInstagram : '',
        contactEmail: supportsContacts ? cleanEmail : '',
        openingHours: supportsContacts ? host.openingHours : const {},
        ownerUid: supportsContacts
            ? (owner?.uid ?? '')
            : host.widget.spot.ownerUid,
        ownerUsername: supportsContacts
            ? (owner?.username ?? '')
            : host.widget.spot.ownerUsername,
        photoUrl: finalPhotoUrls.isEmpty ? '' : finalPhotoUrls.first,
        photoUrls: finalPhotoUrls,
        verifiedOnly: host.verifiedOnlySpot,
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
        clearTemporarySchedule: !host.isTemporarySpot,
        clearTemporaryMapReveal:
            !host.isTemporarySpot || !host.temporaryShowOnMapAtEnabled,
      );

      final editChangeSummary = <String>[];
      if (host.widget.spot.name != updatedSpot.name) {
        editChangeSummary.add(
          'Name: ${host.widget.spot.name} → ${updatedSpot.name}',
        );
      }
      if (host.widget.spot.cityCountry != updatedSpot.cityCountry) {
        editChangeSummary.add(
          'Location text: ${host.widget.spot.cityCountry} → ${updatedSpot.cityCountry}',
        );
      }
      if (host.widget.spot.description != updatedSpot.description) {
        editChangeSummary.add('Description changed');
      }
      if ((host.widget.spot.coordinates.latitude -
                      updatedSpot.coordinates.latitude)
                  .abs() >
              0.000001 ||
          (host.widget.spot.coordinates.longitude -
                      updatedSpot.coordinates.longitude)
                  .abs() >
              0.000001) {
        editChangeSummary.add('Map position changed');
      }
      if (primarySpotCategory(host.widget.spot) !=
          primarySpotCategory(updatedSpot)) {
        editChangeSummary.add(
          'Category: ${primarySpotCategory(host.widget.spot)} → ${primarySpotCategory(updatedSpot)}',
        );
      }
      if (host.widget.spot.photoUrls.length != updatedSpot.photoUrls.length ||
          host.widget.spot.photoUrl != updatedSpot.photoUrl) {
        editChangeSummary.add('Photos changed');
      }
      if (host.widget.spot.isTemporary != updatedSpot.isTemporary ||
          host.widget.spot.startsAtMillis != updatedSpot.startsAtMillis ||
          host.widget.spot.expiresAtMillis != updatedSpot.expiresAtMillis ||
          host.widget.spot.showOnMapAtMillis != updatedSpot.showOnMapAtMillis) {
        editChangeSummary.add('Temporary schedule changed');
      }

      final needsEditReview =
          !userRoleIsStaff(currentUser.role) &&
          host.widget.spot.addedByUid == currentUser.uid;

      if (host.widget.reviewLease != null)
        await host.widget.reviewLease!.ensureActive();

      await spotsCollection().doc(host.widget.spot.id).debugUpdate({
        'name': updatedSpot.name,
        'cityCountry': updatedSpot.cityCountry,
        'countryCode': updatedSpot.effectiveCountryCode,
        'description': updatedSpot.description,
        'lat': updatedSpot.coordinates.latitude,
        'lng': updatedSpot.coordinates.longitude,
        'coordinates': GeoPoint(
          updatedSpot.coordinates.latitude,
          updatedSpot.coordinates.longitude,
        ),
        'categories': updatedSpot.categories,
        'reelLink': updatedSpot.reelLink,
        'contactPhone': updatedSpot.contactPhone,
        'contactInstagram': updatedSpot.contactInstagram,
        'contactEmail': updatedSpot.contactEmail,
        'openingHours': openingHoursToFirebase(updatedSpot.openingHours),
        'ownerUid': updatedSpot.ownerUid,
        'ownerUsername': updatedSpot.ownerUsername,
        'photoUrl': updatedSpot.photoUrl,
        'photoUrls': updatedSpot.photoUrls,
        'verifiedOnly': updatedSpot.verifiedOnly,
        'isTemporary': updatedSpot.isTemporary,
        'startsAt': updatedSpot.startsAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(updatedSpot.startsAtMillis!),
        'expiresAt': updatedSpot.expiresAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(
                updatedSpot.expiresAtMillis!,
              ),
        'showOnMapAt': updatedSpot.showOnMapAtMillis == null
            ? null
            : Timestamp.fromMillisecondsSinceEpoch(
                updatedSpot.showOnMapAtMillis!,
              ),
        if (needsEditReview) 'status': 'edited',
        if (needsEditReview) 'editReviewStatus': 'pending',
        if (needsEditReview) 'editChangeSummary': editChangeSummary,
        if (userRoleIsStaff(currentUser.role))
          'reviewSessionId':
              host.widget.reviewLease?.sessionId ?? FieldValue.delete(),
        'editedBy': currentUser.username,
        'editedByUid': currentUser.uid,
        'editedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final localUpdatedAtMillis = DateTime.now().millisecondsSinceEpoch;
      final visibleUpdatedSpot =
          (needsEditReview
                  ? updatedSpot.copyWith(status: SpotStatus.edited)
                  : updatedSpot)
              .copyWith(updatedAtMillis: localUpdatedAtMillis);

      if (needsEditReview) {
        try {
          await createAdminSpotEditReviewNotification(visibleUpdatedSpot);
        } catch (error, stack) {
          // The spot was saved successfully; notification failure must not
          // report a failed edit or encourage the user to submit it twice.
          debugPrint('Edited spot review notification failed: $error');
          debugPrint('$stack');
        }
      }

      // Update the shared source cache immediately as well as the screen-level
      // notifiers below. Without this, an older approved/temporary listener
      // source can temporarily win and expose the previous coordinates before
      // the edited reveal time.
      upsertSpotIntoLocalImmediateCache(visibleUpdatedSpot);

      reviewSpots.value = reviewSpots.value
          .map(
            (item) =>
                isSameSpot(item, host.widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      submittedSpots.value = submittedSpots.value
          .map(
            (item) =>
                isSameSpot(item, host.widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();
      savedSpots.value = savedSpots.value
          .map(
            (item) =>
                isSameSpot(item, host.widget.spot) ? visibleUpdatedSpot : item,
          )
          .toList();

      if (!(host.mounted && viewContext.mounted)) {
        return;
      }

      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: blue,
          content: CcsText(
            needsEditReview ? 'Spot edit sent for review.' : 'Spot updated.',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      Navigator.pop(viewContext, true);
    } catch (error) {
      if (!(host.mounted && viewContext.mounted)) {
        return;
      }
      showAdminActionError(
        viewContext,
        message: 'Could not save spot',
        error: error,
      );
    } finally {
      if ((host.mounted && viewContext.mounted)) {
        host.updateView(() => host.isSaving = false);
      }
    }
  }
}
