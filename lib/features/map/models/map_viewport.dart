import 'package:latlong2/latlong.dart';

/// Last actual rendered main-map camera, independent of the chosen spot pin.
class MapViewport {
  const MapViewport(this.center, this.zoom, this.bearing, this.pitch);
  final LatLng center;
  final double zoom, bearing, pitch;
}

MapViewport? mainMapViewport;
