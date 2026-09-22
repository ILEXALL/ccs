import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class VerifiedSpotBadge extends StatelessWidget {
  final double size;

  const VerifiedSpotBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: blue,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: math.max(1.0, size * 0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: blue.withValues(alpha: 0.55),
            blurRadius: math.max(5.0, size * 0.42),
            spreadRadius: math.max(0.4, size * 0.04),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: math.max(3.0, size * 0.24),
          ),
        ],
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.68),
    );
  }
}

class TemporaryMapBadge extends StatelessWidget {
  const TemporaryMapBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.orangeAccent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.48),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const CcsText(
        'NOW',
        style: TextStyle(
          color: Colors.black,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          height: 1,
        ),
      ),
    );
  }
}
