import 'package:flutter/material.dart';
import '../models/road_speed.dart';

class RoadSpeedHud extends StatelessWidget {
  const RoadSpeedHud({super.key, this.speedKmh, this.limit});
  final double? speedKmh;
  final ApplicableRoadLimit? limit;
  @override
  Widget build(BuildContext context) {
    if (speedKmh == null || !speedKmh!.isFinite || speedKmh! < 10) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final valid = limit?.usableAt(now) == true;
    final speeding = valid && limit!.isOverspeed(speedKmh, now);
    return Semantics(
      label:
          'Road speed limit ${valid ? limit!.kilometersPerHour.round() : "unavailable"}. GPS speed ${speedKmh?.round() ?? "unavailable"} kilometers per hour',
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: valid
                    ? 'Road speed limit · ${limit!.source}'
                    : 'Road speed limit unavailable',
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: valid ? Colors.red : Colors.grey,
                      width: 3,
                    ),
                  ),
                  child: Text(
                    valid ? '${limit!.kilometersPerHour.round()}' : '—',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    speedKmh == null ? '—' : '${speedKmh!.round()}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: speeding
                          ? Colors.red
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Text('km/h', style: TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
