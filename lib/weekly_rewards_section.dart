import 'package:flutter/material.dart';

class WeeklyRewardsSection extends StatelessWidget {
  final String language;
  final Map? weekly;
  const WeeklyRewardsSection({super.key, required this.language, this.weekly});

  String t(String en, String ru, String lv) => language == 'ru' ? ru : language == 'lv' ? lv : en;

  @override
  Widget build(BuildContext context) {
    final items = (weekly?['items'] as List? ?? []).cast<Map>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.event_note_outlined, color: Color(0xFF4F91FF)),
        const SizedBox(width: 10),
        Expanded(child: Text(t('Weekly tasks', 'Задания недели', 'Nedēļas uzdevumi'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 8),
      Text(t('Preview · Not active yet', 'Предварительный план · Ещё не активны',
        'Priekšskatījums · Vēl nav aktīvi'), style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 14),
      if (items.isEmpty) Text(t('Tasks are being prepared', 'Задания готовятся', 'Uzdevumi tiek gatavoti')),
      for (final item in items) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF141A24),
            borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF28394F))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(switch (item['difficulty']) {
                1 => t('Medium', 'Среднее', 'Vidējs'),
                2 => t('Hard', 'Сложное', 'Grūts'),
                _ => t('Easy', 'Простое', 'Viegls'),
              }, style: const TextStyle(color: Colors.white60, fontSize: 12))),
              Text('+${item['xp']} XP', style: const TextStyle(color: Color(0xFF72D8AE), fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text((item['title'] as Map)[language] as String? ?? (item['title'] as Map)['en'] as String,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.lock_outline, size: 15, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(child: Text(t('Not available yet', 'Пока недоступно', 'Vēl nav pieejams'),
                style: const TextStyle(fontSize: 12, color: Colors.white54))),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (items.isNotEmpty) Text(t('Planned: 300 XP within the 3,000 weekly limit',
        'План: 300 XP в пределах недельного лимита 3000',
        'Plānots: 300 XP nedēļas 3000 XP limita ietvaros'),
        style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }
}
