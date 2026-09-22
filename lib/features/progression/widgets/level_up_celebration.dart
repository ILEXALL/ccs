import 'package:flutter/material.dart';

import '../../../core/localization/app_language.dart';
import 'xp_summary.dart' show XpLevelWheel;

/// Compact, non-blocking feedback above the app's 62px bottom navigation.
class LevelUpCelebration extends StatelessWidget {
  const LevelUpCelebration({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom + 12
        : media.padding.bottom + 62 + 12;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: media.disableAnimations ? 0 : 260),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - value)),
                child: child,
              ),
            ),
            child: AnimatedBuilder(
              animation: appUiPreferences,
              builder: (context, _) {
                final (title, subtitle) = switch (appUiPreferences.language) {
                  AppLanguage.en => (
                    'New level unlocked',
                    'Driver level $level',
                  ),
                  AppLanguage.ru => (
                    'Новый уровень открыт',
                    'Уровень водителя $level',
                  ),
                  AppLanguage.lv => (
                    'Atbloķēts jauns līmenis',
                    'Vadītāja līmenis $level',
                  ),
                };
                return Semantics(
                  liveRegion: true,
                  label: '$title. $subtitle',
                  child: ExcludeSemantics(
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 440),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF171B22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF414852)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 12,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            XpLevelWheel(
                              level: level,
                              accentColor: Colors.transparent,
                              size: 38,
                            ),
                            const SizedBox(width: 10),
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 38,
                                minHeight: 38,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: const Color(0xFF7C9BC2),
                                ),
                              ),
                              child: Text(
                                '$level',
                                style: const TextStyle(
                                  color: Color(0xFF9FC5F5),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: Color(0xFFA8AFBA),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
