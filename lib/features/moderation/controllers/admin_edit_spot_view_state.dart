import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/moderation/data/spot_review_lease.dart'
    show SpotReviewLease;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData;

abstract interface class AdminEditSpotInputs {
  CarSpot get spot;
  SpotReviewLease? get reviewLease;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class AdminEditSpotViewState {
  BuildContext get context;
  bool get mounted;
  AdminEditSpotInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get nameController;
  TextEditingController get cityController;
  TextEditingController get latController;
  TextEditingController get lngController;
  TextEditingController get descriptionController;
  TextEditingController get reelController;
  TextEditingController get phoneController;
  TextEditingController get instagramController;
  TextEditingController get emailController;
  String get selectedCategory;
  set selectedCategory(String value);
  bool get verifiedOnlySpot;
  set verifiedOnlySpot(bool value);
  bool get isTemporarySpot;
  set isTemporarySpot(bool value);
  DateTime? get temporaryStartsAt;
  set temporaryStartsAt(DateTime? value);
  DateTime? get temporaryExpiresAt;
  set temporaryExpiresAt(DateTime? value);
  bool get temporaryShowOnMapAtEnabled;
  set temporaryShowOnMapAtEnabled(bool value);
  DateTime? get temporaryShowOnMapAt;
  set temporaryShowOnMapAt(DateTime? value);
  List<String> get existingPhotoUrls;
  List<String> get newPhotoPaths;
  Map<int, OpeningHoursData> get openingHours;
  set openingHours(Map<int, OpeningHoursData> value);
  SpotOwnerAssignment? get selectedOwner;
  set selectedOwner(SpotOwnerAssignment? value);
  bool get isSaving;
  set isSaving(bool value);
  bool get isUpdatingEditLocation;
  set isUpdatingEditLocation(bool value);
  AdminEditSpotContentActions get content;
  AdminEditSpotControllerActions get controller;
}

abstract interface class AdminEditSpotContentActions {
  Widget photoThumb({
    required int index,
    required String label,
    required String source,
    required VoidCallback onRemove,
    required bool isLocal,
  });
}

abstract interface class AdminEditSpotControllerActions {
  int get totalPhotoCount;
  Future<void> addPhoto();
  void removeExistingPhotoAt(int index);
  void removeNewPhotoAt(int index);
  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue);
  Future<void> chooseTemporaryStart();
  Future<void> chooseTemporaryEnd();
  Future<void> chooseTemporaryShowOnMapAt();
  Future<void> applyEditedLocation(LatLng location);
  Future<void> chooseEditedLocationOnMap();
  Future<void> chooseEditedLocationByAddress();
  Future<void> chooseEditedCurrentLocation();
  Future<void> saveSpot();
}
