import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ccs_app/features/map/widgets/visit_dwell_marker.dart';
import 'package:ccs_app/core/config/app_config.dart' show spotVisitUrl;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show canViewGroupSpot;
import 'package:ccs_app/features/progression/data/xp_api.dart'
    show xpScreenRequest;
import 'package:ccs_app/features/spots/data/spot_filters.dart'
    show approvedPublicSpots;
import 'package:ccs_app/features/spots/data/spot_regions.dart'
    show lookupSpotLocationRegion;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/shared/models/countries.dart' show localizedCountryName;

final _countryAchievementRequests = <String>{};

final _creditedSpotVisits = <String, DateTime>{};

final _lastMockLocationReport = <String, DateTime>{};

final visitDwellProgress = ValueNotifier<VisitDwellProgress?>(null);

bool _visitSampleInFlight = false;

Future<void> checkGpsSpotVisits(Position position) async {
  final user = FirebaseAuth.instance.currentUser;
  final now = DateTime.now();
  if (user != null &&
      position.isMocked &&
      now.difference(_lastMockLocationReport[user.uid] ?? DateTime(1970)) >
          const Duration(minutes: 5)) {
    _lastMockLocationReport[user.uid] = now;
    unawaited(
      xpScreenRequest('location_check', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'recordedAtMillis': position.timestamp.millisecondsSinceEpoch,
        'isMocked': true,
      }).catchError((_) => <String, dynamic>{}),
    );
  }
  if (user == null ||
      position.isMocked ||
      !position.accuracy.isFinite ||
      position.accuracy < 0 ||
      position.accuracy > 100 ||
      now.difference(position.timestamp).abs() > const Duration(seconds: 60)) {
    if (visitDwellProgress.value != null) {
      visitDwellProgress.value = null;
      if (user != null)
        unawaited(
          xpScreenRequest(
            'reset_spot_visit',
          ).catchError((_) => <String, dynamic>{}),
        );
    }
    return;
  }
  final candidates = approvedPublicSpots()
      .where(
        (spot) =>
            canViewGroupSpot(spot) &&
            spot.isVisibleOnMapNow &&
            (!spot.isTemporary || spot.isTemporaryActiveNow) &&
            Geolocator.distanceBetween(
                  position.latitude,
                  position.longitude,
                  spot.coordinates.latitude,
                  spot.coordinates.longitude,
                ) <=
                100,
      )
      .toList();
  if (_visitSampleInFlight) return;
  final current = visitDwellProgress.value;
  candidates.sort(
    (a, b) =>
        Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          a.coordinates.latitude,
          a.coordinates.longitude,
        ).compareTo(
          Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            b.coordinates.latitude,
            b.coordinates.longitude,
          ),
        ),
  );
  CarSpot? spot;
  if (current?.userId == user.uid) {
    for (final candidate in candidates) {
      if (candidate.id == current!.spotId) spot = candidate;
    }
  }
  spot ??= candidates.isEmpty ? null : candidates.first;
  // Send an outside sample for the previous target so departure resets server state.
  final spotId =
      spot?.id ?? (current?.userId == user.uid ? current?.spotId : null);
  if (spotId == null) {
    visitDwellProgress.value = null;
    return;
  }
  final key = '${user.uid}/$spotId';
  if (spot != null &&
      current?.spotId == spotId &&
      now.difference(_creditedSpotVisits[key] ?? DateTime(1970)) <
          const Duration(seconds: 15))
    return;
  _visitSampleInFlight = true;
  try {
    final token = await user.getIdToken();
    final fix = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'isMocked': position.isMocked,
      'recordedAtMillis': position.timestamp.millisecondsSinceEpoch,
    };
    final response = await postJsonToUrl(
      spotVisitUrl,
      {'spotId': spotId, 'gpsFix': fix},
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
    if (response['ok'] == true) {
      _creditedSpotVisits[key] = now;
      final result = response['result'] as Map;
      if (result['status'] == 'outside_or_invalid') {
        visitDwellProgress.value = null;
      } else {
        final wasCompleted =
            current?.spotId == spotId && current?.completed == true;
        visitDwellProgress.value = VisitDwellProgress(
          userId: user.uid,
          spotId: spotId,
          elapsedMs: (result['elapsedMs'] as num? ?? 0).toInt(),
          requiredMs: (result['requiredMs'] as num? ?? 300000).toInt(),
          completed: result['recorded'] == true,
          receivedAt: DateTime.now(),
        );
        if (result['recorded'] == true && !wasCompleted)
          await xpScreenRequest('visit_country', fix);
      }
    }
  } catch (error) {
    visitDwellProgress.value = null;
    debugPrint('Spot visit check failed: $error');
  } finally {
    _visitSampleInFlight = false;
  }
}

Future<void> checkGpsCountryAchievement(
  BuildContext context,
  Position position,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null ||
      position.isMocked ||
      !position.accuracy.isFinite ||
      position.accuracy > 1000 ||
      !_countryAchievementRequests.add(uid))
    return;
  try {
    final region = await lookupSpotLocationRegion(
      LatLng(position.latitude, position.longitude),
    );
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    final result = await xpScreenRequest('visit_country', {
      'countryCode': region.countryCode,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'recordedAtMillis': position.timestamp.millisecondsSinceEpoch,
      'isMocked': position.isMocked,
    });
    if (result['awarded'] == true &&
        context.mounted &&
        FirebaseAuth.instance.currentUser?.uid == uid) {
      final country = localizedCountryName(result['countryCode'] as String);
      final message = switch (appUiPreferences.language) {
        AppLanguage.en => 'Country achievement unlocked: $country (+75 XP)',
        AppLanguage.ru => 'Достижение страны получено: $country (+75 XP)',
        AppLanguage.lv => 'Valsts sasniegums atbloķēts: $country (+75 XP)',
      };
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: CcsText(message)));
    }
  } catch (error) {
    // GPS navigation and sharing must still work if the XP service is offline.
    debugPrint('Country achievement check failed: $error');
  } finally {
    _countryAchievementRequests.remove(uid);
  }
}
