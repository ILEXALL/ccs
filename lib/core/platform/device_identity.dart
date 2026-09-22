import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show uniqueNonEmptyStrings;
import 'package:ccs_app/core/platform/platform_bridges.dart'
    show deviceIdentityChannel;

const appDeviceIdStorageKey = 'ccs_app_device_id_v1';

String generateAppDeviceId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String cleanDeviceIdForStorage(String value) {
  return value.trim().replaceAll('/', '_');
}

Future<String?> getNativeAppDeviceId() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }

  try {
    final deviceId = await deviceIdentityChannel.invokeMethod<String>(
      'getDeviceId',
    );
    final cleanDeviceId = cleanDeviceIdForStorage(deviceId ?? '');
    return cleanDeviceId.isEmpty ? null : cleanDeviceId;
  } on MissingPluginException {
    return null;
  } on PlatformException catch (error) {
    debugPrint('Native device id unavailable: ${error.message ?? error.code}');
    return null;
  }
}

Future<String> getOrCreateLegacyAppDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(appDeviceIdStorageKey)?.trim() ?? '';

  if (existing.isNotEmpty) {
    return cleanDeviceIdForStorage(existing);
  }

  final created = generateAppDeviceId();
  await prefs.setString(appDeviceIdStorageKey, created);
  return created;
}

Future<List<String>> getAppDeviceIds() async {
  final nativeDeviceId = await getNativeAppDeviceId();
  final legacyDeviceId = await getOrCreateLegacyAppDeviceId();

  return uniqueNonEmptyStrings([?nativeDeviceId, legacyDeviceId]);
}

Future<String> getOrCreateAppDeviceId() async {
  return (await getAppDeviceIds()).first;
}
