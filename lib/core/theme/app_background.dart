import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/theme/app_theme.dart'
    show appMapBackgroundImage, night;

class AppMapBackground extends StatelessWidget {
  const AppMapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: night),
          CustomPaint(
            painter: AppMapBackgroundPainter(appMapBackgroundImage),
            child: const SizedBox.expand(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.36),
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.02)),
        ],
      ),
    );
  }
}

class AppMapBackgroundPainter extends CustomPainter {
  final ui.Image? image;

  const AppMapBackgroundPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null || size.isEmpty) {
      return;
    }

    final inputSize = Size(image.width.toDouble(), image.height.toDouble());
    final outputRect = Offset.zero & size;
    final fitted = applyBoxFit(BoxFit.cover, inputSize, size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & inputSize,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      outputRect,
    );
    final paint = Paint()..filterQuality = FilterQuality.high;

    canvas.drawImageRect(image, sourceRect, destinationRect, paint);
  }

  @override
  bool shouldRepaint(AppMapBackgroundPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

class AppRouteBackground extends StatelessWidget {
  final Widget child;

  const AppRouteBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const AppMapBackground(), child],
    );
  }
}

PageRoute<T> appPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return AnimatedBuilder(
        animation: appUiPreferences,
        builder: (context, _) => AppRouteBackground(child: builder(context)),
      );
    },
  );
}
