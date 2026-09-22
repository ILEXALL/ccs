import 'package:latlong2/latlong.dart';

const mapRigaCenter = LatLng(56.9496, 24.1052);

const mapRigaZoom = 11.25;

const mapFullSpotIconMinZoom = 11.25;

const double mapSpotFogFullZoom = 5.2;

const double mapSpotFogFadeOutZoom = 8.2;

const Duration mapLiveLocationUploadInterval = Duration(seconds: 60);

const double mapLiveLocationMinimumUploadDistanceMeters = 0;

const double mapGpsCourseMinSpeedMetersPerSecond = 0.8;

const double mapGpsCourseBaseMovementMeters = 2.2;

const double mapPoliceReportVoteRadiusMeters = 300;

const double mapPoliceReportDuplicateRadiusMeters = 500;

const double mapSosAutoCheckRadiusMeters = 500;

const Duration mapSosNoAnswerAutoRemoveDelay = Duration(minutes: 5);

const Duration mapPoliceReportCreatorVoteCooldown = Duration(minutes: 15);
