import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/map/models/map_style.dart' show CcsMapStyle;

const spotCategoryOptions = [
  'Drift',
  'Photo',
  'Meet',
  'Drive',
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Drag',
  'Track',
  'Activity',
  'Off-road',
  'Food',
  'Scrap',
];

const contactEnabledSpotCategories = {
  'Service',
  'Detailing',
  'Wash',
  'Store',
  'Food',
  'Track',
  'Activity',
  'Scrap',
};

bool spotCategorySupportsContacts(String category) {
  return contactEnabledSpotCategories.contains(category.trim());
}

const spotCategoryIconAssets = {
  'Drift': 'assets/spot_icons/drift.png',
  'Photo': 'assets/spot_icons/photo.png',
  'Meet': 'assets/spot_icons/meet.png',
  'Drive': 'assets/spot_icons/drive.png',
  'Service': 'assets/spot_icons/service.png',
  'Detailing': 'assets/spot_icons/detailing.png',
  'Wash': 'assets/spot_icons/wash.png',
  'Store': 'assets/spot_icons/store_2.png',
  'Drag': 'assets/spot_icons/drag.png',
  'Track': 'assets/spot_icons/track.png',
  'Activity': 'assets/spot_icons/activity.png',
  'Off-road': 'assets/spot_icons/offroad.png',
  'Food': 'assets/spot_icons/food.png',
  'Scrap': 'assets/spot_icons/scrap.png',
};

// Dark map uses the regular white category icons.
// Light CCS map uses the dark/black *_light icons that are already in assets.
// Police and SOS markers are not part of this map and stay identical on both map styles.
const spotCategoryLightIconAssets = {
  'Drift': 'assets/spot_icons/drift_light.png',
  'Photo': 'assets/spot_icons/photo_light.png',
  'Meet': 'assets/spot_icons/meet_light.png',
  'Drive': 'assets/spot_icons/drive_light.png',
  'Service': 'assets/spot_icons/service_light.png',
  'Detailing': 'assets/spot_icons/detailing_light.png',
  'Wash': 'assets/spot_icons/wash_light.png',
  'Store': 'assets/spot_icons/store_light_2.png',
  'Drag': 'assets/spot_icons/drag_light.png',
  'Track': 'assets/spot_icons/track_light.png',
  'Activity': 'assets/spot_icons/activity_light.png',
  'Off-road': 'assets/spot_icons/offroad_light.png',
  'Food': 'assets/spot_icons/food_light.png',
  'Scrap': 'assets/spot_icons/scrap_light.png',
};

const spotCategoryColors = {
  'Drift': Color(0xFF829600),
  'Photo': Color(0xFF9B35FF),
  'Meet': Color(0xFF8AE600),
  'Drive': Color(0xFF00B8FF),
  'Service': Color(0xFFFFD400),
  'Detailing': Color(0xFF00E0C7),
  'Wash': Color(0xFF008CFF),
  'Store': Color(0xFFFF7A00),
  'Drag': Color(0xFFFF1635),
  'Track': Color(0xFF00F5A0),
  'Activity': Color(0xFFFF6652),
  'Off-road': Color(0xFF8B5A2B),
  'Food': Color(0xFFFF1B8D),
  'Scrap': Color(0xFF9AA9BC),
};

String spotIconAssetPathForCategory(String category, {CcsMapStyle? mapStyle}) {
  final assets = mapStyle == CcsMapStyle.light
      ? spotCategoryLightIconAssets
      : spotCategoryIconAssets;

  return assets[category] ??
      assets['Photo'] ??
      spotCategoryIconAssets[category] ??
      spotCategoryIconAssets['Photo']!;
}

Color spotColorForCategory(String category) {
  return spotCategoryColors[category] ?? blue;
}
