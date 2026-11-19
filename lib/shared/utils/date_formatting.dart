String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatShortDateTime(DateTime value) {
  value = value.toLocal();
  return '${twoDigits(value.day)}.${twoDigits(value.month)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String formatClockTime(DateTime value) {
  value = value.toLocal();
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

bool isSameLocalDate(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String formatShortDate(DateTime value) {
  value = value.toLocal();
  return '${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}';
}
