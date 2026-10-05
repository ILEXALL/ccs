import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/map/models/globe_spot_style.dart';

List<Map<String, Object?>> globeContextSpots({String? excludeId}) => [
  for (final spot in approvedPublicSpots())
    if (spot.id != excludeId && spot.isVisibleOnMapNow)
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [
            spot.coordinates.longitude,
            spot.coordinates.latitude,
          ],
        },
        'properties': {
          'kind': 'spot',
          'id': spot.id,
          'label': spot.name,
          ...globeSpotStyle(spot),
        },
      },
];
