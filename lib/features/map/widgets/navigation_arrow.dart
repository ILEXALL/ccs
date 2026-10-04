import 'dart:math' as math;
import 'package:flutter/material.dart';

double navigationBlend(double elapsedSeconds) => elapsedSeconds.isFinite
    ? 1 - math.exp(-elapsedSeconds.clamp(0.0, 0.1) / 0.09)
    : 0;

double interpolateCourse(double from, double to, double amount) {
  if (!from.isFinite) from = 0;
  if (!to.isFinite || !amount.isFinite) return from;
  final delta = ((to - from + 540) % 360) - 180;
  return (from + delta * amount.clamp(0.0, 1.0) + 360) % 360;
}

// About 35 km across at Riga's latitude, adjusted for phone/tablet width.
double cityOverviewZoom(double width) => width.isFinite && width > 0
    ? (10 + math.log(width / 400) / math.ln2).clamp(9.0, 11.25).toDouble()
    : 10;

double navigationArrowSize(double zoom) {
  final t = ((zoom.isFinite ? zoom : 3) - 3).clamp(0.0, 13.0) / 13;
  return 18 + 44 * t;
}

/// North-facing arrow; the map layer supplies the camera's rotation.
class NavigationArrow extends StatelessWidget {
  final double headingDegrees;
  final double pulse;
  const NavigationArrow({
    super.key,
    required this.headingDegrees,
    this.pulse = 0,
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Transform.rotate(
      angle: (headingDegrees.isFinite ? headingDegrees : 0) * math.pi / 180,
      child: CustomPaint(
        painter: NavigationArrowPainter(
          pulse.isFinite ? pulse.clamp(0.0, 1.0) : 0,
        ),
        size: Size(62, 62),
      ),
    ),
  );
}

class NavigationArrowPainter extends CustomPainter {
  final double pulse;
  const NavigationArrowPainter(this.pulse);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 62, size.height / 62);
    final eased = Curves.easeInOut.transform(pulse);
    canvas.translate(31, 31);
    canvas.scale(0.94 + 0.06 * eased);
    canvas.translate(-31, -31);
    canvas.drawCircle(
      const Offset(31, 31),
      29,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF00BFFF).withValues(alpha: 0.25 + 0.25 * eased),
            const Color(0x0000BFFF),
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 62, 62)),
    );
    final arrow = Path()
      ..moveTo(31, 11)
      ..lineTo(46, 48)
      ..quadraticBezierTo(47, 50, 44, 49)
      ..lineTo(31, 42)
      ..lineTo(18, 49)
      ..quadraticBezierTo(15, 50, 16, 48)
      ..close();
    canvas.drawShadow(arrow, const Color(0xFF00BFFF), 7, true);
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = const Color(0xFF00BFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant NavigationArrowPainter oldDelegate) =>
      oldDelegate.pulse != pulse;
}

/// A north reset belongs only to the gesture that leaves GPS following.
class FollowExitGesture {
  final Set<int> _pointers = {};
  bool get isActive => _pointers.isNotEmpty;
  bool _canReset = false;
  double _startZoom = 0;

  void pointerDown(
    int pointer, {
    required bool following,
    required double zoom,
  }) {
    if (_pointers.isEmpty) {
      _canReset = following;
      _startZoom = zoom;
    }
    _pointers.add(pointer);
  }

  void pointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) _canReset = false;
  }

  bool consumeZoomOut(double zoom) {
    // Ignore small scale jitter while the user rotates their fingers.
    if (!_canReset || !zoom.isFinite || zoom >= _startZoom - 0.08) return false;
    _canReset = false;
    return true;
  }
}
