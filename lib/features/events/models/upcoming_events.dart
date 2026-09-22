import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

Map<String, List<CarSpot>> groupUpcomingTemporarySpots(
  Iterable<CarSpot> spots, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  // Calendar dates, rather than 24-hour durations, keep DST boundaries correct.
  final tomorrow = DateTime(current.year, current.month, current.day + 1);
  final dayAfterTomorrow = DateTime(
    current.year,
    current.month,
    current.day + 2,
  );
  final nextWeek = DateTime(
    current.year,
    current.month,
    current.day + DateTime.sunday - current.weekday + 1,
  );
  final weekAfterNext = DateTime(
    nextWeek.year,
    nextWeek.month,
    nextWeek.day + 7,
  );
  final nextMonth = DateTime(current.year, current.month + 1, 1);
  final monthAfterNext = DateTime(current.year, current.month + 2, 1);
  final groups = <String, List<CarSpot>>{
    'Today': [],
    'Tomorrow': [],
    'This week': [],
    'Next week': [],
    'This month': [],
    'Next month': [],
    'Later': [],
  };
  final currentMillis = current.millisecondsSinceEpoch;
  for (final spot in spots) {
    final starts = spot.startsAtMillis;
    final expires = spot.expiresAtMillis;
    if (!spot.isTemporary ||
        starts == null ||
        expires == null ||
        expires <= starts ||
        expires <= currentMillis) {
      continue;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(starts);
    final group = date.isBefore(tomorrow)
        ? 'Today'
        : date.isBefore(dayAfterTomorrow)
        ? 'Tomorrow'
        : date.isBefore(nextWeek)
        ? 'This week'
        : date.isBefore(weekAfterNext)
        ? 'Next week'
        : date.isBefore(nextMonth)
        ? 'This month'
        : date.isBefore(monthAfterNext)
        ? 'Next month'
        : 'Later';
    groups[group]!.add(spot);
  }
  for (final group in groups.values) {
    group.sort((a, b) {
      final aActive = a.startsAtMillis! <= currentMillis;
      final bActive = b.startsAtMillis! <= currentMillis;
      if (aActive != bActive) return aActive ? -1 : 1;
      final byTime = a.startsAtMillis!.compareTo(b.startsAtMillis!);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }
  groups.removeWhere((_, spots) => spots.isEmpty);
  return groups;
}
