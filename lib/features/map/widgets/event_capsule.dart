import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Selected Capsule artwork, with a constant usable hit area independent of zoom.
class EventCapsule extends StatelessWidget {
  const EventCapsule({
    super.key,
    required this.light,
    required this.label,
    required this.width,
    required this.onTap,
    this.dot = false,
  });
  final bool light, dot;
  final String label;
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xff1457ef),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: dot ? 9 : 10,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Event $label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: math.max(44, width),
          height: math.max(
            44,
            width * 36 / 128 +
                (label.isEmpty
                    ? 0
                    : label.contains('\n')
                    ? 32
                    : 20),
          ),
          child: dot
              ? Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: width,
                      height: width,
                      decoration: BoxDecoration(
                        color: const Color(0xff1457ef),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: .7),
                      ),
                    ),
                    if (label.isNotEmpty)
                      Positioned(left: 26, bottom: 23, child: badge),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/globe/event-capsule-${light ? 'light' : 'dark'}.png',
                      width: width,
                      height: width * 36 / 128,
                    ),
                    if (label.isNotEmpty) ...[const SizedBox(height: 3), badge],
                  ],
                ),
        ),
      ),
    );
  }
}
