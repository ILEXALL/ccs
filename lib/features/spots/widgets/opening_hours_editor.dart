import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/models/opening_hours.dart'
    show
        OpeningHoursData,
        clockTextFromTimeOfDay,
        minutesFromClockText,
        openingHoursAreTwentyFourSeven,
        weekdayLabels;

class OpeningHoursEditor extends StatefulWidget {
  final Map<int, OpeningHoursData> openingHours;
  final ValueChanged<Map<int, OpeningHoursData>> onChanged;

  const OpeningHoursEditor({
    super.key,
    required this.openingHours,
    required this.onChanged,
  });

  @override
  State<OpeningHoursEditor> createState() => _OpeningHoursEditorState();
}

class _OpeningHoursEditorState extends State<OpeningHoursEditor> {
  late bool useCustomHours;
  final Set<int> manuallyAdjustedWeekdays = <int>{};

  @override
  void initState() {
    super.initState();
    useCustomHours = !openingHoursAreTwentyFourSeven(widget.openingHours);
  }

  @override
  void didUpdateWidget(covariant OpeningHoursEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEqualsOpeningHours(oldWidget.openingHours, widget.openingHours)) {
      useCustomHours = !openingHoursAreTwentyFourSeven(widget.openingHours);
    }
  }

  bool mapEqualsOpeningHours(
    Map<int, OpeningHoursData> first,
    Map<int, OpeningHoursData> second,
  ) {
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      final a = first[weekday];
      final b = second[weekday];
      if (a == null && b == null) {
        continue;
      }
      if (a == null || b == null) {
        return false;
      }
      if (a.isOpen != b.isOpen ||
          a.opensAt != b.opensAt ||
          a.closesAt != b.closesAt) {
        return false;
      }
    }

    return true;
  }

  OpeningHoursData dayData(int weekday) {
    return widget.openingHours[weekday] ??
        const OpeningHoursData(
          isOpen: true,
          opensAt: '00:00',
          closesAt: '23:59',
        );
  }

  Map<int, OpeningHoursData> fullTwentyFourSevenHours() {
    return {
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        weekday: const OpeningHoursData(
          isOpen: true,
          opensAt: '00:00',
          closesAt: '23:59',
        ),
    };
  }

  Map<int, OpeningHoursData> normalWorkingHours() {
    return {
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        weekday: OpeningHoursData(
          isOpen: weekday <= DateTime.friday,
          opensAt: '08:00',
          closesAt: '20:00',
        ),
    };
  }

  void setMode(bool custom) {
    setState(() {
      useCustomHours = custom;
      manuallyAdjustedWeekdays.clear();
    });

    if (custom) {
      final currentIs247 = openingHoursAreTwentyFourSeven(widget.openingHours);
      widget.onChanged(
        currentIs247 ? normalWorkingHours() : widget.openingHours,
      );
    } else {
      widget.onChanged(fullTwentyFourSevenHours());
    }
  }

  void updateDay(int weekday, OpeningHoursData value) {
    final nextHours = {...widget.openingHours};

    if (weekday == DateTime.monday) {
      nextHours[weekday] = value;

      for (
        var otherWeekday = DateTime.tuesday;
        otherWeekday <= DateTime.sunday;
        otherWeekday++
      ) {
        if (!manuallyAdjustedWeekdays.contains(otherWeekday)) {
          nextHours[otherWeekday] = value;
        }
      }
    } else {
      manuallyAdjustedWeekdays.add(weekday);
      nextHours[weekday] = value;
    }

    widget.onChanged(nextHours);
  }

  Future<void> pickTime({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
  }) async {
    final day = dayData(weekday);
    final currentValue = opensAt ? day.opensAt : day.closesAt;
    final currentMinutes = minutesFromClockText(currentValue) ?? 8 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      ),
      builder: (context, child) {
        return Theme(data: ThemeData.dark(), child: child!);
      },
    );

    if (picked == null) {
      return;
    }

    final nextTime = clockTextFromTimeOfDay(picked);
    updateDay(
      weekday,
      opensAt
          ? day.copyWith(opensAt: nextTime)
          : day.copyWith(closesAt: nextTime),
    );
  }

  Widget timeButton({
    required BuildContext context,
    required int weekday,
    required bool opensAt,
    required String value,
  }) {
    return OutlinedButton.icon(
      onPressed: () =>
          pickTime(context: context, weekday: weekday, opensAt: opensAt),
      icon: Icon(opensAt ? Icons.login : Icons.logout, size: 15),
      label: CcsText(value),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? blue.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? blue : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? blue : Colors.white54, size: 18),
              const SizedBox(width: 7),
              CcsText(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!useCustomHours) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              modeButton(
                label: '24/7',
                icon: Icons.all_inclusive,
                selected: true,
                onTap: () => setMode(false),
              ),
              const SizedBox(width: 8),
              modeButton(
                label: 'Custom',
                icon: Icons.schedule,
                selected: false,
                onTap: () => setMode(true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: CcsText(
                    'Open all day, every day. Switch to Custom to set opening and closing times.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            modeButton(
              label: '24/7',
              icon: Icons.all_inclusive,
              selected: false,
              onTap: () => setMode(false),
            ),
            const SizedBox(width: 8),
            modeButton(
              label: 'Custom',
              icon: Icons.schedule,
              selected: true,
              onTap: () => setMode(true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (
          var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++
        )
          Padding(
            padding: EdgeInsets.only(
              bottom: weekday == DateTime.sunday ? 0 : 10,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CcsText(
                              weekdayLabels[weekday] ?? 'Day',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: dayData(weekday).isOpen,
                        activeThumbColor: blue,
                        onChanged: (value) => updateDay(
                          weekday,
                          dayData(weekday).copyWith(isOpen: value),
                        ),
                      ),
                    ],
                  ),
                  if (dayData(weekday).isOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: true,
                            value: dayData(weekday).opensAt,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: timeButton(
                            context: context,
                            weekday: weekday,
                            opensAt: false,
                            value: dayData(weekday).closesAt,
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: CcsText(
                        'Closed',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
