String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatShortDateTime(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String formatClockTime(DateTime value) {
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

bool isSameLocalDate(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String formatShortDate(DateTime value) {
  return '${twoDigits(value.day)}.${twoDigits(value.month)}.${value.year}';
}
