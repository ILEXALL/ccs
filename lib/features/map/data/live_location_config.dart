const liveLocationDisclaimerDismissedKey = 'live_location_disclaimer_dismissed';

const liveLocationDurationChoices = <Duration>[
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];

const liveLocationStaleAfter = Duration(minutes: 30);

const double liveLocationSpotStaleKeepRadiusMeters = 200;

const userLocationLookupTimeout = Duration(seconds: 15);

const publicLiveLocationAudienceMarker = '__public__';

const regularUserCarIconAsset = 'assets/user_cars/car_green.png';

const verifiedUserCarIconAsset = 'assets/user_cars/car_blue.png';

const friendUserCarIconAsset = 'assets/user_cars/car_purple.png';

const double friendNearbyRadiusMeters = 5000;

const double friendAtSpotRadiusMeters = 200;

const Duration friendAtSpotNotificationDwellTime = Duration(minutes: 5);

const Duration friendLocationNotificationCooldown = Duration(minutes: 30);
