import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show mapFromFirebase, stringFromFirebase;

const weekdayLabels = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

class OpeningHoursData {
  final bool isOpen;
  final String opensAt;
  final String closesAt;

  const OpeningHoursData({
    required this.isOpen,
    required this.opensAt,
    required this.closesAt,
  });

  OpeningHoursData copyWith({bool? isOpen, String? opensAt, String? closesAt}) {
    return OpeningHoursData(
      isOpen: isOpen ?? this.isOpen,
      opensAt: opensAt ?? this.opensAt,
      closesAt: closesAt ?? this.closesAt,
    );
  }

  factory OpeningHoursData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);

    return OpeningHoursData(
      isOpen: data['isOpen'] == true,
      opensAt: stringFromFirebase(data['opensAt'], '08:00'),
      closesAt: stringFromFirebase(data['closesAt'], '20:00'),
    );
  }

  Map<String, Object?> toFirebase() {
    return {'isOpen': isOpen, 'opensAt': opensAt, 'closesAt': closesAt};
  }
}

Map<int, OpeningHoursData> defaultServiceOpeningHours() {
  return {
    for (var weekday = 1; weekday <= 7; weekday++)
      weekday: const OpeningHoursData(
        isOpen: true,
        opensAt: '00:00',
        closesAt: '23:59',
      ),
  };
}

bool openingHoursAreTwentyFourSeven(Map<int, OpeningHoursData> openingHours) {
  for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
    final day = openingHours[weekday];
    if (day == null ||
        !day.isOpen ||
        day.opensAt.trim() != '00:00' ||
        day.closesAt.trim() != '23:59') {
      return false;
    }
  }

  return true;
}

Map<int, OpeningHoursData> openingHoursFromFirebase(Object? value) {
  final data = mapFromFirebase(value);
  final openingHours = <int, OpeningHoursData>{};

  for (final entry in data.entries) {
    final weekday = int.tryParse(entry.key);
    if (weekday == null ||
        weekday < DateTime.monday ||
        weekday > DateTime.sunday) {
      continue;
    }

    openingHours[weekday] = OpeningHoursData.fromFirebase(entry.value);
  }

  return openingHours;
}

Map<String, Object?> openingHoursToFirebase(
  Map<int, OpeningHoursData> openingHours,
) {
  return {
    for (final entry in openingHours.entries)
      '${entry.key}': entry.value.toFirebase(),
  };
}

int? minutesFromClockText(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

String clockTextFromTimeOfDay(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
