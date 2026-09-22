import 'package:flutter/material.dart' hide Text;

class CurrentUserPulseDot extends StatelessWidget {
  final Animation<double> animation;

  const CurrentUserPulseDot({super.key, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final pulse = Curves.easeInOutCubic.transform(animation.value);
        final outerSize = 30 + pulse * 20;
        final middleSize = 22 + pulse * 8;

        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(
                      0xFF25D9FF,
                    ).withValues(alpha: 0.48 - pulse * 0.24),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF00B7FF,
                      ).withValues(alpha: 0.36 - pulse * 0.12),
                      blurRadius: 16 + pulse * 14,
                      spreadRadius: 2 + pulse * 5,
                    ),
                  ],
                ),
              ),
              Container(
                width: middleSize,
                height: middleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1AAFFF).withValues(alpha: 0.16),
                  border: Border.all(
                    color: const Color(0xFF7EEBFF).withValues(alpha: 0.62),
                    width: 1,
                  ),
                ),
              ),
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Colors.white,
                      Color(0xFF85F4FF),
                      Color(0xFF008DFF),
                    ],
                    stops: [0.0, 0.42, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.88),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C8FF).withValues(alpha: 0.72),
                      blurRadius: 11 + pulse * 6,
                      spreadRadius: 1.6,
                    ),
                  ],
                ),
              ),
              Container(
                width: 4.2,
                height: 4.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
