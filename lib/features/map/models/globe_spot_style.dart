import 'package:flutter/material.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/models/spot_business_status.dart';
import 'package:ccs_app/features/spots/widgets/spot_icon_style.dart';
import 'map_style.dart';

/// Share the standard map's category selection, palette and business states.
Map<String, Object> globeSpotStyle(CarSpot spot) {
  final closed = spotIsClosedNow(spot);
  final event = spot.isTemporaryActiveNow || spot.isTemporaryUpcomingOnMap;
  final color = closed && !spot.isTemporaryActiveNow
      ? Colors.grey.shade700
      : event
      ? Colors.orangeAccent
      : spotColorForSpot(spot);
  return {
    'icon': spotIconAssetPathForSpot(spot, mapStyle: CcsMapStyle.dark),
    'lightIcon': spotIconAssetPathForSpot(spot, mapStyle: CcsMapStyle.light),
    'color':
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
    'opacity': closed || spot.isTemporaryUpcomingOnMap ? 0.8 : 1.0,
    'event': event,
    'tint': closed || spot.isTemporaryUpcomingOnMap,
  };
}
