import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show OpeningHoursData, minutesFromClockText, weekdayLabels;

class SpotBusinessStatus {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const SpotBusinessStatus({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

String nextOpeningLabel(Map<int, OpeningHoursData> openingHours, int weekday) {
  for (var offset = 1; offset <= 7; offset++) {
    final nextWeekday = ((weekday - 1 + offset) % 7) + 1;
    final nextDay = openingHours[nextWeekday];
    if (nextDay != null && nextDay.isOpen) {
      return '${weekdayLabels[nextWeekday] ?? 'Next day'} at ${nextDay.opensAt}';
    }
  }

  return 'No upcoming opening hours';
}

SpotBusinessStatus businessStatusForSpot(CarSpot spot) {
  if (spot.openingHours.isEmpty) {
    return const SpotBusinessStatus(
      title: 'Hours not added',
      subtitle: 'The owner has not added opening hours yet.',
      icon: Icons.schedule,
      color: Colors.white54,
    );
  }

  final now = DateTime.now();
  final today = spot.openingHours[now.weekday];
  final weekdayName = weekdayLabels[now.weekday] ?? 'Today';

  if (today == null || !today.isOpen) {
    return SpotBusinessStatus(
      title: 'Closed today',
      subtitle: '$weekdayName is marked as closed.',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  final opensAt = minutesFromClockText(today.opensAt);
  final closesAt = minutesFromClockText(today.closesAt);
  final nowMinutes = now.hour * 60 + now.minute;

  if (opensAt == null || closesAt == null) {
    return const SpotBusinessStatus(
      title: 'Hours need update',
      subtitle: 'Opening hours are not formatted correctly.',
      icon: Icons.error_outline,
      color: Colors.orangeAccent,
    );
  }

  final isOpenNow = closesAt > opensAt
      ? nowMinutes >= opensAt && nowMinutes < closesAt
      : nowMinutes >= opensAt || nowMinutes < closesAt;

  if (isOpenNow) {
    return SpotBusinessStatus(
      title: 'Open now',
      subtitle: 'Today ${today.opensAt} - ${today.closesAt}',
      icon: Icons.check,
      color: Colors.greenAccent,
    );
  }

  if (closesAt > opensAt && nowMinutes < opensAt) {
    return SpotBusinessStatus(
      title: 'Closed now',
      subtitle: 'Opens today at ${today.opensAt}',
      icon: Icons.close,
      color: Colors.redAccent,
    );
  }

  return SpotBusinessStatus(
    title: 'Closed now',
    subtitle: 'Opens ${nextOpeningLabel(spot.openingHours, now.weekday)}',
    icon: Icons.close,
    color: Colors.redAccent,
  );
}

bool spotIsClosedNow(CarSpot spot) {
  if (!spot.supportsContacts || !spot.hasOpeningHours) {
    return false;
  }

  final status = businessStatusForSpot(spot);
  return status.title == 'Closed now' || status.title == 'Closed today';
}
