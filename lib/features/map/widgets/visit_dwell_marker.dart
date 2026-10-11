import 'dart:async';
import 'package:flutter/material.dart';

/// Server-confirmed dwell, with visual interpolation that never completes a visit.
class VisitDwellProgress {
  final String userId;
  final String spotId;
  final int elapsedMs;
  final int requiredMs;
  final bool completed;
  final DateTime receivedAt;
  const VisitDwellProgress({
    required this.userId,
    required this.spotId,
    required this.elapsedMs,
    required this.requiredMs,
    required this.completed,
    required this.receivedAt,
  });
  double fraction(DateTime now) {
    final age = now.difference(receivedAt).inMilliseconds;
    if (age > 60000) return 0;
    if (completed) return 1;
    return ((elapsedMs + age.clamp(0, 20000)) / requiredMs).clamp(0, 0.99);
  }
}

class VisitDwellMarker extends StatefulWidget {
  final Widget child;
  final VisitDwellProgress? progress;
  final String label;
  final double diameter;
  const VisitDwellMarker({
    super.key,
    required this.child,
    required this.progress,
    required this.label,
    this.diameter = 48,
  });
  @override
  State<VisitDwellMarker> createState() => _VisitDwellMarkerState();
}

class _VisitDwellMarkerState extends State<VisitDwellMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse;
  bool celebrating = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    updateTimer();
  }

  @override
  void didUpdateWidget(covariant VisitDwellMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress?.completed == true &&
        oldWidget.progress?.completed == false &&
        widget.progress?.spotId == oldWidget.progress?.spotId) {
      celebrating = true;
      pulse
        ..stop()
        ..duration = const Duration(milliseconds: 2400)
        ..forward(from: 0);
    } else if (widget.progress?.completed != true) {
      celebrating = false;
    }
    updateTimer();
  }

  void updateTimer() {
    timer?.cancel();
    if (widget.progress != null && !widget.progress!.completed) {
      if (!pulse.isAnimating) {
        pulse.duration = const Duration(milliseconds: 1400);
        pulse.repeat(reverse: true);
      }
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress == null ||
        (progress.completed && !celebrating) ||
        DateTime.now().difference(progress.receivedAt).inSeconds > 60) {
      pulse.stop();
      return widget.child;
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final completion = progress.completed;
        if (completion && pulse.value >= 1) return widget.child;
        final color = completion
            ? const Color(0xFF91EDBC)
            : const Color(0xFF83EDFF);
        final opacity = completion
            ? ((1 - pulse.value) / .3).clamp(0.0, 1.0)
            : 1.0;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            widget.child,
            IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: Semantics(
                  label: widget.label,
                  child: SizedBox(
                    width: widget.diameter,
                    height: widget.diameter,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (completion)
                          Transform.scale(
                            scale: 1 + pulse.value * .85,
                            child: Opacity(
                              opacity: 1 - pulse.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color, width: 2),
                                ),
                              ),
                            ),
                          ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color.withValues(alpha: .2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(
                                  alpha: completion
                                      ? .35
                                      : .1 + pulse.value * .1,
                                ),
                                blurRadius: completion
                                    ? 12
                                    : 5 + pulse.value * 4,
                              ),
                            ],
                          ),
                        ),
                        if (!completion)
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progress.fraction(DateTime.now()),
                              strokeWidth: 5,
                              strokeCap: StrokeCap.round,
                              color: color,
                              backgroundColor: const Color(0x44328EB3),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF15352D),
                              border: Border.all(color: color, width: 4),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check_rounded,
                                color: color,
                                size: widget.diameter * .55,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
