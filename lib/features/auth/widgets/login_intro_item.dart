import 'package:flutter/material.dart' hide Text;

class SplashIntroItem extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> fadeAnimation;
  final Widget child;
  final double travel;

  const SplashIntroItem({
    super.key,
    required this.animation,
    required this.fadeAnimation,
    required this.child,
    this.travel = 96,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final easedValue = animation.value;
        final opacity = fadeAnimation.value.clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - easedValue) * travel),
            child: child,
          ),
        );
      },
    );
  }
}
