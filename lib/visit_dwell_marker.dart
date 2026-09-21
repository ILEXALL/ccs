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
  const VisitDwellMarker({
    super.key,
    required this.child,
    required this.progress,
    required this.label,
  });
  @override
  State<VisitDwellMarker> createState() => _VisitDwellMarkerState();
}

class _VisitDwellMarkerState extends State<VisitDwellMarker> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    updateTimer();
  }

  @override
  void didUpdateWidget(covariant VisitDwellMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateTimer();
  }

  void updateTimer() {
    timer?.cancel();
    if (widget.progress != null)
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress == null ||
        DateTime.now().difference(progress.receivedAt).inSeconds > 60)
      return widget.child;
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FittedBox(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Semantics(
                    label: widget.label,
                    value:
                        '${(progress.fraction(DateTime.now()) * 100).floor()}%',
                    child: CircularProgressIndicator(
                      value: progress.fraction(DateTime.now()),
                      strokeWidth: 3,
                      color: progress.completed
                          ? Colors.greenAccent
                          : Colors.cyanAccent,
                      backgroundColor: Colors.black38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
