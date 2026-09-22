import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

const photoPickerChannel = MethodChannel('ccs/photo_picker');

const deviceIdentityChannel = MethodChannel('ccs/device_identity');

const screenAwakeChannel = MethodChannel('ccs/screen_awake');

const liveLocationBackgroundChannel = MethodChannel(
  'ccs/live_location_background',
);

const systemNotificationsChannel = MethodChannel('ccs/system_notifications');

const appBadgeChannel = MethodChannel('ccs/app_badge');

Future<void> setAppIconBadgeCount(int count) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  final safeCount = count < 0 ? 0 : count;

  try {
    await appBadgeChannel.invokeMethod<void>('setBadgeCount', {
      'count': safeCount,
    });
  } on MissingPluginException {
    // Older installed builds may not have the native badge channel yet.
  } catch (error, stack) {
    debugPrint('App icon badge update failed: $error');
    debugPrint('$stack');
  }
}

Future<void> setScreenAwakeForMap(bool enabled) async {
  if (!Platform.isAndroid) {
    return;
  }

  try {
    await screenAwakeChannel.invokeMethod('setKeepScreenOn', {
      'enabled': enabled,
    });
  } catch (_) {
    // Keeping the screen awake is a comfort feature; the map still works.
  }
}
