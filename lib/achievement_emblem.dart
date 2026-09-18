import 'dart:math' as math;
import 'package:flutter/material.dart';

String achievementCategoryLabel(String category, String language) {
  const labels = {
    'spots': ['Spots', 'Споты', 'Vietas'],
    'visits': ['Visits', 'Посещения', 'Apmeklējumi'],
    'meets': ['Events', 'События', 'Pasākumi'],
    'topics': ['Topics', 'Темы', 'Tēmas'],
    'tenure': ['CCS veteran', 'Стаж CCS', 'CCS stāžs'],
    'moderator': ['Moderator', 'Модератор', 'Moderators'],
    'reports': ['Reports', 'Репорты', 'Ziņojumi'],
    'groups': ['Groups', 'Группы', 'Grupas'],
    'tourist': ['Tourist', 'Турист', 'Ceļotājs'],
  };
  return (labels[category] ?? labels['spots']!)[language == 'ru'
      ? 1
      : language == 'lv'
      ? 2
      : 0];
}

const achievementTierColors = [
  Color(0xFFCE935D),
  Color(0xFFCBD9E4),
  Color(0xFFFFD36C),
  Color(0xFF83DCFA),
  Color(0xFFAD9CF7),
];

class AchievementEmblem extends StatelessWidget {
  final Map<String, dynamic> item;
  const AchievementEmblem({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final tier = (item['tier'] as int? ?? 1).clamp(1, 5);
    final category = item['category'] as String? ?? 'spots';
    final color = achievementTierColors[tier - 1];
    final icon = switch (category) {
      'spots' => Icons.location_on_rounded,
      'visits' => Icons.route_rounded,
      'meets' => Icons.directions_car_rounded,
      'topics' => Icons.forum_rounded,
      'tenure' => Icons.timelapse_rounded,
      'moderator' => Icons.admin_panel_settings_rounded,
      'reports' => Icons.report_outlined,
      'groups' => Icons.groups_rounded,
      _ => Icons.workspace_premium_rounded,
    };
    return Semantics(
      image: true,
      label: '${item['category']} ${item['threshold']}',
      child: SizedBox(
        width: 88,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EmblemSurface(
                  color,
                  tier,
                  category == 'moderator',
                  category == 'tenure',
                ),
              ),
            ),
            Positioned(
              top: category == 'tenure' ? 32 : 26,
              child: category == 'tenure'
                  ? Image.asset(
                      'assets/ccs_logo.png',
                      width: 59,
                      height: 24,
                      fit: BoxFit.contain,
                    )
                  : Icon(
                      icon,
                      size: category == 'tenure' ? 29 : 35,
                      color: color,
                      shadows: [
                        const Shadow(
                          color: Colors.black,
                          offset: Offset(0, 2),
                          blurRadius: 2,
                        ),
                        Shadow(
                          color: color.withValues(alpha: .32),
                          blurRadius: 8,
                        ),
                      ],
                    ),
            ),
            Positioned(
              bottom: 7,
              child: Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF151921),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: color.withValues(alpha: .6)),
                ),
                child: Text(
                  '${item['threshold']}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmblemSurface extends CustomPainter {
  final Color color;
  final int tier;
  final bool shield;
  final bool circle;
  const _EmblemSurface(this.color, this.tier, this.shield, this.circle);
  Path shape(Rect rect) {
    if (circle)
      return Path()..addOval(
        Rect.fromCircle(center: rect.center, radius: rect.shortestSide / 2),
      );
    if (shield) {
      return Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.top + rect.height * .18)
        ..lineTo(rect.right - 3, rect.center.dy)
        ..quadraticBezierTo(
          rect.right - 4,
          rect.bottom - 10,
          rect.center.dx,
          rect.bottom,
        )
        ..quadraticBezierTo(
          rect.left + 4,
          rect.bottom - 10,
          rect.left + 3,
          rect.center.dy,
        )
        ..lineTo(rect.left, rect.top + rect.height * .18)
        ..close();
    }
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = (i * 45 + 22.5) * math.pi / 180;
      final point =
          rect.center +
          Offset(
            math.cos(angle) * rect.width / 2,
            math.sin(angle) * rect.height / 2,
          );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(6, 5, size.width - 12, size.height - 17);
    final outer = shape(rect);
    canvas.drawShadow(outer, Colors.black, 5, true);
    canvas.drawPath(
      outer,
      Paint()
        ..color = color.withValues(alpha: .28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .55)!,
            color,
            Color.lerp(color, Colors.black, .7)!,
            color,
          ],
        ).createShader(rect),
    );
    final inner = shape(rect.deflate(5));
    canvas.drawPath(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF333A45), Color(0xFF171D26), Color(0xFF0D121B)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipPath(inner);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: .19),
            Colors.transparent,
            color.withValues(alpha: .07),
          ],
        ).createShader(rect),
    );
    // Fixed microtexture, not randomized on repaint: stable at profile-icon sizes.
    final grain = Paint()..color = Colors.white.withValues(alpha: .055);
    for (var y = 10; y < 88; y += 4) {
      for (var x = 8; x < 84; x += 4) {
        canvas.drawCircle(
          Offset(x + (y % 8 == 0 ? 1.5 : 0), y.toDouble()),
          .42,
          grain,
        );
      }
    }
    canvas.restore();
    canvas.drawPath(
      shape(rect.deflate(7)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = color.withValues(alpha: .36),
    );
  }

  @override
  bool shouldRepaint(_EmblemSurface oldDelegate) =>
      color != oldDelegate.color ||
      tier != oldDelegate.tier ||
      shield != oldDelegate.shield ||
      circle != oldDelegate.circle;
}
