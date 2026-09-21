import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const firstLaunchGpsPermissionKey = 'gps_permission_prompted_v2';
Future<void> _permissionQueue = Future<void>.value();

/// Android/iOS permission dialogs must not compete with one another.
Future<T> runPermissionRequest<T>(Future<T> Function() request) {
  final result = _permissionQueue.then((_) => request());
  _permissionQueue = result.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  return result;
}

Future<void>? _startupLocation;
Future<Position?>? startupPosition;
Position? warmedStartupPosition;

/// Run after the authenticated home screen first renders, never on login.
Future<void> initializeStartupLocation() => _startupLocation ??= _initialize();

Future<void> requestFirstLaunchGpsPermission({
  required SharedPreferences preferences,
  required Future<LocationPermission> Function() check,
  required Future<LocationPermission> Function() request,
}) async {
  await runPermissionRequest(() async {
    if (preferences.getBool(firstLaunchGpsPermissionKey) == true) return;
    final permission = await check();
    if (permission == LocationPermission.denied) await request();
    // Persist only after the OS request finishes, not before a competing dialog.
    await preferences.setBool(firstLaunchGpsPermissionKey, true);
  });
}

Future<void> _initialize() async {
  try {
    await requestFirstLaunchGpsPermission(
      preferences: await SharedPreferences.getInstance(),
      check: Geolocator.checkPermission,
      request: Geolocator.requestPermission,
    );
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse)
      return;
    if (!await Geolocator.isLocationServiceEnabled()) return;
    // Start warming a real fix while the user is still on the opening page.
    startupPosition = _warmPosition();
  } catch (_) {
    // Allow retry when the map opens after an interrupted OS dialog.
    _startupLocation = null;
  }
}

Future<Position?> _warmPosition() async {
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 12),
      ),
    );
    warmedStartupPosition = position;
    return position;
  } catch (_) {
    return null;
  }
}

/// Existing grants must not wait behind notification/onboarding dialogs.
Future<bool> mapLocationPermissionReady({
  required Future<LocationPermission> Function() check,
  required Future<void> Function() finishFirstLaunchPrompt,
}) async {
  var permission = await check();
  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse)
    return true;
  if (permission == LocationPermission.deniedForever) return false;
  await finishFirstLaunchPrompt();
  permission = await check();
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}
