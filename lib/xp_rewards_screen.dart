import 'package:flutter/material.dart';
import 'weekly_rewards_section.dart';

class XpRewardsScreen extends StatefulWidget {
  final String language;
  final void Function(String spotId)? onOpenSpot;
  final Future<Map<String, dynamic>> Function() load;
  const XpRewardsScreen({
    super.key,
    required this.language,
    required this.load,
    this.onOpenSpot,
  });
  @override
  State<XpRewardsScreen> createState() => _XpRewardsScreenState();
}

class _XpRewardsScreenState extends State<XpRewardsScreen> {
  late Future<Map<String, dynamic>> result;
  String filter = 'all';
  String t(String en, String ru, String lv) => widget.language == 'ru'
      ? ru
      : widget.language == 'lv'
      ? lv
      : en;
  int count(Map item, String key) => (item[key] as num? ?? 0).toInt();
  bool pending(Map item) => count(item, 'pending') > 0;
  bool earned(Map item) => count(item, 'completed') > 0;
  bool matches(Map item) => switch (filter) {
    'pending' => pending(item),
    'earned' => earned(item),
    'todo' => !earned(item) && !pending(item),
    _ => true,
  };
  @override
  void initState() {
    super.initState();
    result = widget.load();
  }

  void refresh() => setState(() {
    result = widget.load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0F13),
    appBar: AppBar(
      title: Text(t('Rewards', 'Награды', 'Atlīdzības')),
      actions: [
        IconButton(
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
          tooltip: t('Refresh', 'Обновить', 'Atjaunot'),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    'Could not load rewards',
                    'Не удалось загрузить награды',
                    'Neizdevās ielādēt atlīdzības',
                  ),
                ),
                TextButton(
                  onPressed: refresh,
                  child: Text(t('Retry', 'Повторить', 'Mēģināt vēlreiz')),
                ),
              ],
            ),
          );
        }
        final items = (snapshot.data?['items'] as List? ?? []).cast<Map>();
        final initial = items.where((i) => i['repeatable'] != true).toList();
        final recurring = items.where((i) => i['repeatable'] == true).toList();
        final done = initial.where(earned).length;
        final waiting = items.fold<int>(0, (n, i) => n + count(i, 'pending'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            WeeklyRewardsSection(
              language: widget.language,
              weekly: snapshot.data?['weekly'] as Map?,
              onOpenSpot: widget.onOpenSpot,
            ),
            const SizedBox(height: 22),
            Text(
              t('Your rewards', 'Твои награды', 'Tavas atlīdzības'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'First steps: $done / ${initial.length}',
                'Первые шаги: $done / ${initial.length}',
                'Pirmie soļi: $done / ${initial.length}',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
            if (waiting > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t(
                    '$waiting awards awaiting XP',
                    'Ожидают начисления: $waiting',
                    '$waiting atlīdzības gaida piešķiršanu',
                  ),
                  style: const TextStyle(color: Color(0xFFFFC66D)),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in <String, String>{
                  'all': t('All', 'Все', 'Visas'),
                  'todo': t('Not completed', 'Не выполнено', 'Nav izpildīts'),
                  'earned': t('XP received', 'XP получен', 'XP saņemts'),
                  'pending': t('Pending', 'Ожидают', 'Gaida'),
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: filter == entry.key,
                    onSelected: (_) => setState(() {
                      filter = entry.key;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (initial.isNotEmpty)
              group(
                'initial',
                t('First steps', 'Первые шаги', 'Pirmie soļi'),
                t(
                  'One-time rewards · $done / ${initial.length}',
                  'Один раз · $done / ${initial.length}',
                  'Vienreizējas atlīdzības · $done / ${initial.length}',
                ),
                initial,
                initiallyExpanded:
                    done < initial.length || initial.any(pending),
              ),
            if (recurring.isNotEmpty)
              group(
                'recurring',
                t(
                  'Repeatable rewards',
                  'Повторяемые награды',
                  'Atkārtojamas atlīdzības',
                ),
                t(
                  'Earn again for each new spot',
                  'Можно получать за каждый новый спот',
                  'Saņem par katru jaunu vietu',
                ),
                recurring,
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t(
                    'No rewards yet',
                    'Награды пока не появились',
                    'Atlīdzību vēl nav',
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget group(
    String id,
    String title,
    String subtitle,
    List<Map> items, {
    bool initiallyExpanded = true,
  }) {
    final visible = items.where(matches).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF141A24),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: ValueKey('$id-$filter'),
          initiallyExpanded: filter != 'all' || initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
          children: [
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  t(
                    'No rewards with this status',
                    'Нет наград с таким статусом',
                    'Nav atlīdzību ar šo statusu',
                  ),
                ),
              ),
            for (final category
                in visible.map((i) => i['category']).toSet()) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    switch (category) {
                      'profile' => t('Profile', 'Профиль', 'Profils'),
                      'garage_car' => t(
                        'First car',
                        'Первая машина',
                        'Pirmais auto',
                      ),
                      'spot' => t('Spots', 'Споты', 'Vietas'),
                      _ => t('Activity', 'Активность', 'Aktivitāte'),
                    },
                    style: const TextStyle(
                      color: Colors.white60,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (final item in visible.where(
                (i) => i['category'] == category,
              ))
                rewardCard(item),
            ],
          ],
        ),
      ),
    );
  }

  Widget rewardCard(Map item) {
    final waiting = pending(item);
    final received = earned(item);
    final repeatable = item['repeatable'] == true;
    final color = waiting
        ? const Color(0xFFFFC66D)
        : received
        ? const Color(0xFF72D8AE)
        : const Color(0xFF9BA5B5);
    final titles = item['title'] as Map? ?? {};
    final status = waiting
        ? t('XP pending', 'XP ожидается', 'XP gaida')
        : received
        ? t('XP received', 'XP получен', 'XP saņemts')
        : t('Not completed', 'Не выполнено', 'Nav izpildīts');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: waiting
            ? const Color(0xFF30271A)
            : received
            ? const Color(0xFF173129)
            : const Color(0xFF1A202A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            waiting
                ? Icons.schedule
                : received
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: color,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[widget.language] as String? ??
                      titles['en'] as String? ??
                      '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: received ? Colors.white : const Color(0xFFD2D8E2),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '+${item['xp']} XP',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  repeatable
                      ? t(
                          'Per new spot · received ${count(item, 'completed')} times',
                          'За каждый новый спот · получено ${count(item, 'completed')} раз',
                          'Par katru jaunu vietu · saņemts ${count(item, 'completed')} reizes',
                        )
                      : t(
                          'One-time reward',
                          'Одноразовая награда',
                          'Vienreizēja atlīdzība',
                        ),
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                if (received)
                  Text(
                    t(
                      'Earned: ${count(item, 'earnedXp')} XP',
                      'Получено: ${count(item, 'earnedXp')} XP',
                      'Saņemts: ${count(item, 'earnedXp')} XP',
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF72D8AE),
                    ),
                  ),
                if (waiting)
                  Text(
                    t(
                      'Pending awards: ${count(item, 'pending')}',
                      'Ожидают начисления: ${count(item, 'pending')}',
                      'Gaida piešķiršanu: ${count(item, 'pending')}',
                    ),
                    style: TextStyle(fontSize: 12, color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
