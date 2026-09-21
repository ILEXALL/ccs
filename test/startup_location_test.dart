import 'dart:async';
import 'package:ccs_app/startup_location.dart';
import 'package:ccs_app/navigation_arrow.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opening map with GPS granted bypasses a blocked startup prompt',
    () async {
      final blocked = Completer<void>();
      var promptCalled = false;
      final granted = await mapLocationPermissionReady(
        check: () async => LocationPermission.whileInUse,
        finishFirstLaunchPrompt: () {
          promptCalled = true;
          return blocked.future;
        },
      ).timeout(const Duration(seconds: 1));
      expect(granted, isTrue);
      expect(promptCalled, isFalse);
    },
  );
  test(
    'opening map rechecks permission after first-launch prompt completes',
    () async {
      var permission = LocationPermission.denied;
      expect(
        await mapLocationPermissionReady(
          check: () async => permission,
          finishFirstLaunchPrompt: () async {
            permission = LocationPermission.whileInUse;
          },
        ),
        isTrue,
      );
      expect(
        await mapLocationPermissionReady(
          check: () async => LocationPermission.deniedForever,
          finishFirstLaunchPrompt: () async =>
              throw StateError('unexpected prompt'),
        ),
        isFalse,
      );
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('first launch requests permission once, even after refusal', () async {
    final prefs = await SharedPreferences.getInstance();
    var requests = 0;
    for (var i = 0; i < 2; i++) {
      await requestFirstLaunchGpsPermission(
        preferences: prefs,
        check: () async => LocationPermission.denied,
        request: () async {
          requests++;
          return LocationPermission.denied;
        },
      );
    }
    expect(requests, 1);
  });
  test(
    'granted or permanently denied permission never opens a dialog',
    () async {
      for (final permission in [
        LocationPermission.whileInUse,
        LocationPermission.always,
        LocationPermission.deniedForever,
      ]) {
        SharedPreferences.setMockInitialValues({});
        await requestFirstLaunchGpsPermission(
          preferences: await SharedPreferences.getInstance(),
          check: () async => permission,
          request: () async => throw StateError('Unexpected prompt'),
        );
      }
    },
  );
  test(
    'permission dialogs are serialized, including recovery after an error',
    () async {
      final pending = Completer<void>();
      final first = runPermissionRequest(() => pending.future);
      var secondStarted = false;
      final second = runPermissionRequest(() async {
        secondStarted = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondStarted, isFalse);
      pending.complete();
      await first;
      await second;
      expect(secondStarted, isTrue);
      await expectLater(
        runPermissionRequest<void>(() async => throw StateError('interrupted')),
        throwsStateError,
      );
      expect(await runPermissionRequest(() async => 7), 7);
    },
  );
  test('failed GPS prompt is not remembered and can be retried', () async {
    final prefs = await SharedPreferences.getInstance();
    await expectLater(
      requestFirstLaunchGpsPermission(
        preferences: prefs,
        check: () async => LocationPermission.denied,
        request: () async => throw StateError('another dialog'),
      ),
      throwsStateError,
    );
    expect(prefs.getBool(firstLaunchGpsPermissionKey), isNull);
    var requested = false;
    await requestFirstLaunchGpsPermission(
      preferences: prefs,
      check: () async => LocationPermission.denied,
      request: () async {
        requested = true;
        return LocationPermission.whileInUse;
      },
    );
    expect(requested, isTrue);
    expect(prefs.getBool(firstLaunchGpsPermissionKey), isTrue);
  });
  test('overview is city scale and arrow shrinks at regional zoom', () {
    expect(cityOverviewZoom(400), 10);
    expect(cityOverviewZoom(800), 11);
    expect(cityOverviewZoom(double.nan), 10);
    expect(navigationArrowSize(3), 18);
    expect(navigationArrowSize(10), lessThan(navigationArrowSize(16)));
    expect(navigationArrowSize(18), 62);
  });
}
