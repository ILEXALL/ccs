import 'package:ccs_app/features/events/models/event_date_format.dart';
import 'package:ccs_app/shared/utils/date_formatting.dart' show formatClockTime;
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
      ? const Color(0xFFFFD45A)
      : spotColorForSpot(spot);
  return {
    'icon': spotIconAssetPathForSpot(spot, mapStyle: CcsMapStyle.dark),
    'lightIcon': spotIconAssetPathForSpot(spot, mapStyle: CcsMapStyle.light),
    'color':
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}',
    'opacity': event ? 1.0 : (closed ? 0.8 : 1.0),
    'event': event,
    'eventActive': spot.isTemporaryActiveNow,
    'eventStartLabel': event && spot.startsAtMillis != null
        ? '${formatEventDate(DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!))} · ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!))}'
        : '',
    'tint': !event && closed,
  };
}
