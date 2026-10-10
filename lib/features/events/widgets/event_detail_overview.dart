import 'dart:async';
import 'package:ccs_app/core/time/trusted_clock.dart' show trustedClock;
import 'package:ccs_app/features/spots/navigation/waze_route.dart'
    show openWazeRoute;
import 'package:flutter/material.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatClockTime, isSameLocalDate;
import '../models/event_date_format.dart';

class EventDetailOverview extends StatefulWidget {
  const EventDetailOverview({super.key, required this.spot, this.onShowMap});
  final CarSpot spot;
  final VoidCallback? onShowMap;
  @override
  State<EventDetailOverview> createState() => _EventDetailOverviewState();
}

class _EventDetailOverviewState extends State<EventDetailOverview> {
  CarSpot get spot => widget.spot;
  Timer? _revealTimer;
  late bool _available;
  @override
  void initState() {
    super.initState();
    _available = spot.isTemporaryLocationAvailableNow;
    trustedClock.addListener(_checkReveal);
    _revealTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkReveal(),
    );
  }

  void _checkReveal() {
    final next = spot.isTemporaryLocationAvailableNow;
    if (mounted && next != _available) setState(() => _available = next);
  }

  @override
  void didUpdateWidget(covariant EventDetailOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _available = spot.isTemporaryLocationAvailableNow;
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    trustedClock.removeListener(_checkReveal);
    super.dispose();
  }

  Widget detail(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: const Color(0xFF67B7FF)),
      const SizedBox(width: 7),
      Flexible(
        child: CcsText(
          label,
          style: const TextStyle(
            color: Color(0xFFD4E0EE),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final start = spot.startsAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.startsAtMillis!);
    final end = spot.expiresAtMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(spot.expiresAtMillis!);
    final available = spot.isTemporaryLocationAvailableNow;
    final revealMillis = spot.effectiveShowOnMapAtMillis;
    final reveal = revealMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(revealMillis);
    final revealLabel = communityText(
      en: 'Location reveal',
      ru: 'Открытие локации',
      lv: 'Atrašanās vietas atklāšana',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CcsText(
          spot.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            detail(
              Icons.calendar_month_outlined,
              start == null ? spot.temporaryTimeLabel : formatEventDate(start),
            ),
            if (start != null)
              detail(
                Icons.schedule,
                '${formatClockTime(start)}${end == null ? '' : ' – ${isSameLocalDate(start, end) ? '' : '${formatEventDate(end)} · '}${formatClockTime(end)}'}',
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (available)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onShowMap == null
                      ? null
                      : () {
                          if (spot.isTemporaryLocationAvailableNow)
                            widget.onShowMap!();
                        },
                  icon: const Icon(Icons.map_outlined, size: 19),
                  label: const CcsText('Map'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: const Color(0xFF9BCFFF),
                    side: const BorderSide(color: Color(0xFF325A7D)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (spot.isTemporaryLocationAvailableNow)
                      openWazeRoute(context, spot);
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 19),
                  label: const CcsText('Waze'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: const Color(0xFF175FBE),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF132334),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF29435C)),
            ),
            child: detail(
              available ? Icons.place_outlined : Icons.lock_outline,
              available
                  ? spot.cityCountry
                  : reveal == null
                  ? spot.temporaryLocationAvailableAtLabel
                  : '$revealLabel – ${formatEventDate(reveal)} · ${formatClockTime(reveal)}',
            ),
          ),
      ],
    );
  }
}
