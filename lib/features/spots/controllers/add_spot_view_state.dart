import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    show SpotOwnerAssignment;
import 'package:ccs_app/features/spots/data/spot_regions.dart'
    show SpotLocationRegion;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData;

abstract interface class AddSpotInputs {
  bool get eventMode;
  bool get privateEvent;
}

/// Screen-owned state. The widget retains lifecycle/disposal ownership;
/// action and content modules access only this typed view contract.
abstract interface class AddSpotViewState {
  BuildContext get context;
  bool get mounted;
  AddSpotInputs get widget;
  void updateView(VoidCallback update);
  TextEditingController get nameController;
  TextEditingController get cityController;
  TextEditingController get addressController;
  TextEditingController get descriptionController;
  TextEditingController get reelController;
  TextEditingController get phoneController;
  TextEditingController get instagramController;
  TextEditingController get emailController;
  TextEditingController get addedByController;
  String get selectedCategory;
  set selectedCategory(String value);
  LatLng? get selectedLocation;
  set selectedLocation(LatLng? value);
  SpotLocationRegion? get selectedRegion;
  set selectedRegion(SpotLocationRegion? value);
  int get locationLookupRevision;
  set locationLookupRevision(int value);
  String get detectedCityCountry;
  set detectedCityCountry(String value);
  bool get isDetectingCityCountry;
  set isDetectingCityCountry(bool value);
  bool get isUsingCurrentLocation;
  set isUsingCurrentLocation(bool value);
  List<String> get selectedPhotoPaths;
  bool get verifiedOnlySpot;
  set verifiedOnlySpot(bool value);
  bool get isTemporarySpot;
  set isTemporarySpot(bool value);
  bool get groupVisibility;
  set groupVisibility(bool value);
  Set<String> get selectedGroupIds;
  DateTime? get temporaryStartsAt;
  set temporaryStartsAt(DateTime? value);
  DateTime? get temporaryExpiresAt;
  set temporaryExpiresAt(DateTime? value);
  bool get temporaryShowOnMapAtEnabled;
  set temporaryShowOnMapAtEnabled(bool value);
  DateTime? get temporaryShowOnMapAt;
  set temporaryShowOnMapAt(DateTime? value);
  Map<int, OpeningHoursData> get openingHours;
  set openingHours(Map<int, OpeningHoursData> value);
  SpotOwnerAssignment? get selectedOwner;
  set selectedOwner(SpotOwnerAssignment? value);
  bool get isSubmitting;
  set isSubmitting(bool value);
  AddSpotContentActions get content;
  AddSpotControllerActions get controller;
}

abstract interface class AddSpotContentActions {
  Widget temporaryAudiencePicker();
}

abstract interface class AddSpotControllerActions {
  List<String> get categoryOptions;
  void groupMembershipChanged();
  Future<bool> applySelectedLocation(LatLng location);
  Future<void> chooseLocation();
  Future<void> findExactAddress();
  Future<void> useCurrentLocation();
  Future<void> choosePhoto();
  void removePhotoAt(int index);
  Future<DateTime?> pickTemporaryDateTime(DateTime? initialValue);
  Future<void> chooseTemporaryStart();
  Future<void> chooseTemporaryEnd();
  Future<void> chooseTemporaryShowOnMapAt();
  void resetSpotFormAfterSubmit();
  Future<void> submitSpot();
}
