import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class WeeklyRewardsSection extends StatelessWidget {
  final String language;
  final Map? weekly;
  final void Function(String spotId)? onOpenSpot;
  const WeeklyRewardsSection({
    super.key,
    required this.language,
    this.weekly,
    this.onOpenSpot,
  });
  String t(String en, String ru, String lv) => language == 'ru'
      ? ru
      : language == 'lv'
      ? lv
      : en;
  @override
  Widget build(BuildContext context) {
    if (weekly?['status'] == 'private') return const SizedBox.shrink();
    final items = (weekly?['items'] as List? ?? []).cast<Map>();
    final extras = (weekly?['adminItems'] as List? ?? []).cast<Map>();
    final saved = (weekly?['pendingItems'] as List? ?? []).cast<Map>();
    final active = weekly?['status'] == 'active';
    final preview = weekly == null || weekly?['status'] == 'preview';
    final completed = items
        .where((i) => ['confirmed', 'pending'].contains(i['status']))
        .length;
    final pendingXp = (weekly?['pendingXp'] as num? ?? 0).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_note_outlined, color: Color(0xFF4F91FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t('Weekly tasks', 'Задания недели', 'Nedēļas uzdevumi'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          active
              ? t(
                  'Completed $completed / ${items.length} · resets Monday, Riga time',
                  'Выполнено $completed / ${items.length} · обновление в понедельник по Риге',
                  'Izpildīts $completed / ${items.length} · atjaunojas pirmdien Rīgas laikā',
                )
              : preview
              ? t(
                  'Preview · Not active yet',
                  'Предварительный план · Ещё не активны',
                  'Priekšskatījums · Vēl nav aktīvi',
                )
              : t(
                  'XP rewards are currently disabled',
                  'Начисление XP сейчас отключено',
                  'XP piešķiršana pašlaik izslēgta',
                ),
          style: const TextStyle(color: Colors.white60),
        ),
        if (active) ...[
          const SizedBox(height: 8),
          Text(
            t(
              'Weekly XP: ${weekly?['consumedXp']} / ${weekly?['limit']}',
              'XP за неделю: ${weekly?['consumedXp']} / ${weekly?['limit']}',
              'Nedēļas XP: ${weekly?['consumedXp']} / ${weekly?['limit']}',
            ),
          ),
          if ((weekly?['consumedXp'] as num? ?? 0) >=
              (weekly?['limit'] as num? ?? 3000))
            Text(
              t(
                'Weekly limit reached. New allowance on Monday.',
                'Недельный лимит достигнут. Новый лимит — в понедельник.',
                'Nedēļas limits sasniegts. Jauns limits pirmdien.',
              ),
              style: const TextStyle(color: Color(0xFFFFC66D)),
            ),
          if (pendingXp > 0)
            Text(
              t(
                '$pendingXp XP saved. Awarded when weekly allowance becomes available; no need to repeat the task.',
                '$pendingXp XP сохранено. Начислим, когда обновится лимит; повторять задание не нужно.',
                '$pendingXp XP saglabāts. Piešķirsim, kad būs pieejams nedēļas limits; uzdevums nav jāatkārto.',
              ),
              style: const TextStyle(color: Color(0xFFFFC66D)),
            ),
        ],
        const SizedBox(height: 14),
        if (items.isEmpty)
          Text(
            t(
              'Tasks are being prepared',
              'Задания готовятся',
              'Uzdevumi tiek gatavoti',
            ),
          ),
        for (final item in items) card(item, active: active),
        if (items.isNotEmpty)
          Text(
            preview
                ? t(
                    'Planned: ${weekly?['totalXp'] ?? 300} XP within the 3,000 weekly limit',
                    'План: ${weekly?['totalXp'] ?? 300} XP в пределах недельного лимита 3000',
                    'Plānots: ${weekly?['totalXp'] ?? 300} XP nedēļas 3000 XP limita ietvaros',
                  )
                : t(
                    'All tasks: ${weekly?['totalXp']} XP · actions this week only',
                    'Все задания: ${weekly?['totalXp']} XP · учитываются действия этой недели',
                    'Visi uzdevumi: ${weekly?['totalXp']} XP · tikai šīs nedēļas darbības',
                  ),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t(
                'Spot visits: 50 XP per spot per day after 5 minutes within 100 m. Resets at midnight (Europe/Riga). Events: 400 XP once per event after 5 minutes. Sharing location: 100 XP per full moving hour; stationary time does not count. Leaving or a GPS gap over 1 minute resets the visit timer.',
                'Посещения: 50 XP за спот раз в день после 5 минут в пределах 100 м. Сброс в полночь (Europe/Riga). События: 400 XP один раз за событие после 5 минут. Передача геопозиции: 100 XP за полный час движения; стоянка не учитывается. Выход из радиуса или перерыв GPS больше минуты сбрасывает таймер посещения.',
                'Apmeklējumi: 50 XP par vietu reizi dienā pēc 5 minūtēm 100 m rādiusā. Atiestatīšana pusnaktī (Europe/Riga). Pasākumi: 400 XP vienreiz pēc 5 minūtēm. Kopīgojot atrašanās vietu: 100 XP par pilnu stundu kustībā; stāvēšana neskaitās. Attālinoties vai bez GPS ilgāk par minūti, apmeklējuma taimeris sākas no jauna.',
              ),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            t('Saved rewards', 'Сохранённые награды', 'Saglabātās atlīdzības'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final item in saved) card(item, active: active, saved: true),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            t('From admins', 'От администраторов', 'No administratoriem'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final item in extras) card(item, active: active, custom: true),
        ],
      ],
    );
  }

  Widget card(
    Map item, {
    required bool active,
    bool custom = false,
    bool saved = false,
  }) {
    final received = item['status'] == 'confirmed';
    final waiting = item['status'] == 'pending';
    final color = waiting
        ? const Color(0xFFFFC66D)
        : received
        ? const Color(0xFF72D8AE)
        : const Color(0xFF9BA5B5);
    final target = (item['target'] as num? ?? 1).toInt();
    final progress = (item['progress'] as num? ?? 0).toInt();
    final title = item['title'] as Map? ?? {};
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: waiting
            ? const Color(0xFF30271A)
            : received
            ? const Color(0xFF173129)
            : const Color(0xFF141A24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  saved
                      ? t('Awaiting XP', 'Ожидает XP', 'Gaida XP')
                      : custom
                      ? t(
                          'Special task',
                          'Специальное задание',
                          'Īpašs uzdevums',
                        )
                      : switch (item['difficulty']) {
                          1 => t('Medium', 'Среднее', 'Vidējs'),
                          2 => t('Hard', 'Сложное', 'Grūts'),
                          _ => t('Easy', 'Простое', 'Viegls'),
                        },
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              Text(
                '+${item['xp']} XP',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title[language] as String? ?? title['en'] as String? ?? '',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (custom && item['spotName'] != null)
            Text(
              item['spotName'] as String,
              style: const TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                !active
                    ? Icons.lock_outline
                    : waiting
                    ? Icons.schedule
                    : received
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !active
                      ? t(
                          'Not available yet',
                          'Пока недоступно',
                          'Vēl nav pieejams',
                        )
                      : waiting
                      ? t(
                          'Completed · XP saved',
                          'Выполнено · XP сохранён',
                          'Izpildīts · XP saglabāts',
                        )
                      : received
                      ? t(
                          'Completed · XP received',
                          'Выполнено · XP получен',
                          'Izpildīts · XP saņemts',
                        )
                      : t(
                          'Progress: $progress / $target',
                          'Прогресс: $progress / $target',
                          'Progress: $progress / $target',
                        ),
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
            ],
          ),
          if (active && !received && !waiting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: target > 0 ? (progress / target).clamp(0, 1) : 0,
                color: color,
              ),
            ),
          if (custom && item['endsAt'] is num)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${t('Until', 'До', 'Līdz')}: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['endsAt'] as num).toInt()).toLocal())}',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ),
          if (custom && onOpenSpot != null)
            TextButton.icon(
              onPressed: () => onOpenSpot!(item['spotId'] as String),
              icon: const Icon(Icons.place_outlined),
              label: Text(t('Open location', 'Открыть место', 'Atvērt vietu')),
            ),
        ],
      ),
    );
  }
}
