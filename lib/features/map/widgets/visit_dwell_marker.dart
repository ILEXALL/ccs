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
    if (widget.progress != null && !widget.progress!.completed) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
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
        progress.completed ||
        DateTime.now().difference(progress.receivedAt).inSeconds > 60) {
      return widget.child;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        IgnorePointer(
          child: SizedBox(
            width: widget.diameter,
            height: widget.diameter,
            child: Semantics(
              label: widget.label,
              child: CircularProgressIndicator(
                value: progress.fraction(DateTime.now()),
                strokeWidth: 2,
                color: Colors.cyanAccent,
                backgroundColor: Colors.black38,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
