import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

class TemporarySpotScheduleCard extends StatelessWidget {
  final bool showTypeSwitch;
  final bool enabled;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool showOnMapAtEnabled;
  final DateTime? showOnMapAt;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onShowOnMapAtEnabledChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onPickShowOnMapAt;

  const TemporarySpotScheduleCard({
    super.key,
    this.showTypeSwitch = true,
    required this.enabled,
    required this.startsAt,
    required this.expiresAt,
    required this.showOnMapAtEnabled,
    required this.showOnMapAt,
    required this.onEnabledChanged,
    required this.onShowOnMapAtEnabledChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onPickShowOnMapAt,
  });

  Widget timeButton({
    required String label,
    required DateTime? value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? blue : Colors.white30, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CcsText(
                    trText(label),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CcsText(
                    value == null
                        ? trText('Choose time')
                        : formatShortDateTime(value),
                    softWrap: true,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? blue.withValues(alpha: 0.7) : Colors.white12,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            if (showTypeSwitch)
              SwitchListTile(
                value: enabled,
                onChanged: onEnabledChanged,
                title: CcsText(trText('Event')),
                secondary: const Icon(Icons.event, color: blue),
                contentPadding: EdgeInsets.zero,
              ),
            if (enabled) ...[
              const SizedBox(height: 8),
              timeButton(
                label: 'Starts at',
                value: startsAt,
                icon: Icons.play_arrow,
                onTap: onPickStart,
              ),
              const SizedBox(height: 8),
              timeButton(
                label: 'Ends at',
                value: expiresAt,
                icon: Icons.stop,
                onTap: onPickEnd,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: showOnMapAtEnabled,
                onChanged: enabled ? onShowOnMapAtEnabledChanged : null,
                activeThumbColor: blue,
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.visibility_outlined, color: blue),
                title: CcsText(
                  trText('Show on map at'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: CcsText(
                  trText('Optional delayed map reveal.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              if (showOnMapAtEnabled) ...[
                const SizedBox(height: 8),
                timeButton(
                  label: 'Location visible from',
                  value: showOnMapAt,
                  icon: Icons.map_outlined,
                  onTap: onPickShowOnMapAt,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
