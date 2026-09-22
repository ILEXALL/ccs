import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/notifications/data/push_events.dart'
    show trySendPushNotificationEvent;
import 'package:ccs_app/features/spots/data/spot_state.dart' show reviewSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_status.dart' show SpotStatus;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;

const Duration temporarySpotReminderLeadTime = Duration(hours: 5);

const Duration temporarySpotReminderCheckInterval = Duration(minutes: 1);

Timer? temporarySpotTodayNotificationTimer;

final Set<String> temporarySpotTodayDispatchesThisSession = <String>{};

final Set<String> _temporarySpotReminderInFlight = <String>{};

final Map<String, DateTime> _temporarySpotReminderRetryAfter = {};

String? _temporarySpotReminderSchedulerUid;

bool temporarySpotReminderIsDue(CarSpot spot, DateTime now) {
  if (!spot.isTemporary || spot.status != SpotStatus.approved) {
    return false;
  }
  final startsAtMillis = spot.startsAtMillis;
  if (startsAtMillis == null || spot.id.trim().isEmpty) {
    return false;
  }
  final expiresAtMillis = spot.expiresAtMillis;
  if (expiresAtMillis != null &&
      expiresAtMillis <= now.millisecondsSinceEpoch) {
    return false;
  }
  final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMillis);
  final reminderAt = startsAt.subtract(temporarySpotReminderLeadTime);
  return !now.isBefore(reminderAt) && now.isBefore(startsAt);
}

Future<void> notifyAllUsersIfTemporarySpotIsToday(CarSpot spot) async {
  if (spot.isGroupSpot) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || !userRoleIsStaff(currentUser.role)) return;
  final now = DateTime.now();
  if (!temporarySpotReminderIsDue(spot, now)) return;

  final startsAtMillis = spot.startsAtMillis!;
  final notificationId = 'temporary_spot_reminder_${spot.id}_$startsAtMillis';
  final attemptKey = '$uid|$notificationId';
  final retryAfter = _temporarySpotReminderRetryAfter[attemptKey];
  if (temporarySpotTodayDispatchesThisSession.contains(attemptKey) ||
      _temporarySpotReminderInFlight.contains(attemptKey) ||
      (retryAfter != null && now.isBefore(retryAfter))) {
    return;
  }

  // Claim synchronously, before any await: profile/feed/timer callbacks overlap.
  _temporarySpotReminderInFlight.add(attemptKey);
  _temporarySpotReminderRetryAfter[attemptKey] = now.add(
    const Duration(minutes: 5),
  );
  try {
    // The server owns audience expansion, bell writes and cross-device dedup.
    // Never bulk-read users or rewrite bell items as a client-side fallback.
    final delivered = await trySendPushNotificationEvent({
      'spotId': spot.id,
      'type': 'temporary_spot_today',
      'notificationId': notificationId,
    });
    if (delivered) {
      temporarySpotTodayDispatchesThisSession.add(attemptKey);
      _temporarySpotReminderRetryAfter.remove(attemptKey);
    }
  } finally {
    _temporarySpotReminderInFlight.remove(attemptKey);
  }
}

Future<void> notifyAllUsersAboutTemporarySpotsToday(
  Iterable<CarSpot> spots,
) async {
  final now = DateTime.now();
  final todaySpots =
      spots.where((spot) => temporarySpotReminderIsDue(spot, now)).toList()
        ..sort((first, second) {
          return (first.startsAtMillis ?? 0).compareTo(
            second.startsAtMillis ?? 0,
          );
        });

  for (final spot in todaySpots) {
    await notifyAllUsersIfTemporarySpotIsToday(spot);
  }
}

void stopTemporarySpotTodayNotificationScheduler() {
  temporarySpotTodayNotificationTimer?.cancel();
  temporarySpotTodayNotificationTimer = null;
  _temporarySpotReminderSchedulerUid = null;
  temporarySpotTodayDispatchesThisSession.clear();
}

void startTemporarySpotTodayNotificationScheduler() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || !userRoleIsStaff(currentUser.role)) {
    stopTemporarySpotTodayNotificationScheduler();
    return;
  }
  if (_temporarySpotReminderSchedulerUid == uid &&
      temporarySpotTodayNotificationTimer?.isActive == true) {
    return;
  }
  temporarySpotTodayNotificationTimer?.cancel();
  temporarySpotTodayNotificationTimer = null;
  _temporarySpotReminderSchedulerUid = uid;

  // Dispatch when a temporary spot enters its five-hour reminder window. The
  // immediate check catches app resume/startup; the short cache-only interval
  // keeps an active staff session within about one minute of the target time.
  unawaited(notifyAllUsersAboutTemporarySpotsToday(reviewSpots.value));
  temporarySpotTodayNotificationTimer = Timer.periodic(
    temporarySpotReminderCheckInterval,
    (_) => unawaited(notifyAllUsersAboutTemporarySpotsToday(reviewSpots.value)),
  );
}
