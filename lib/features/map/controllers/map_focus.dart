import 'package:flutter/material.dart' hide Text;
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

final mapFocusRequest = ValueNotifier<MapFocusRequest?>(null);

class MapFocusRequest {
  final String spotId;
  final LatLng coordinates;
  final CarSpot? spot;
  final bool routePreview;
  final int token;

  MapFocusRequest({
    required this.spotId,
    required this.coordinates,
    this.spot,
    this.routePreview = false,
  }) : token = DateTime.now().microsecondsSinceEpoch;
}
