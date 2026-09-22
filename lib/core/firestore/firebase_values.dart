import 'package:cloud_firestore/cloud_firestore.dart';

String stringFromFirebase(Object? value, String fallback) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }

  return fallback;
}

double doubleFromFirebase(Object? value, double fallback) {
  double? parsed;

  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  }

  if (parsed != null && parsed.isFinite) {
    return parsed;
  }

  return fallback;
}

int intFromFirebase(Object? value, int fallback) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  return fallback;
}

int timestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return 0;
}

int? nullableTimestampMillisFromFirebase(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }

  if (value is num) {
    return value.toInt();
  }

  return null;
}

List<String> stringListFromFirebase(Object? value, List<String> fallback) {
  if (value is List) {
    final list = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (list.isNotEmpty) {
      return list;
    }
  }

  return fallback;
}

List<String> uniqueNonEmptyStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];

  for (final value in values) {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty || seen.contains(cleanValue)) {
      continue;
    }

    seen.add(cleanValue);
    result.add(cleanValue);
  }

  return result;
}

bool boolFromFirebase(Object? value, bool fallback) {
  return value is bool ? value : fallback;
}

Map<String, dynamic> mapFromFirebase(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return <String, dynamic>{};
}
