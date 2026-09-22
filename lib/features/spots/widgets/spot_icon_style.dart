import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/features/map/models/map_style.dart' show CcsMapStyle;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_categories.dart'
    show
        spotCategoryIconAssets,
        spotColorForCategory,
        spotIconAssetPathForCategory;

String primarySpotCategory(CarSpot spot) {
  for (final category in spot.categories) {
    if (spotCategoryIconAssets.containsKey(category)) {
      return category;
    }
  }

  return 'Photo';
}

String spotIconAssetPathForSpot(CarSpot spot, {CcsMapStyle? mapStyle}) {
  return spotIconAssetPathForCategory(
    primarySpotCategory(spot),
    mapStyle: mapStyle,
  );
}

Color spotColorForSpot(CarSpot spot) {
  return spotColorForCategory(primarySpotCategory(spot));
}
