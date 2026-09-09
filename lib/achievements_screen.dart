import 'package:flutter/material.dart';

String achievementText(String language, String en, String ru, String lv) =>
    language == 'ru'
    ? ru
    : language == 'lv'
    ? lv
    : en;

class AchievementsScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() load;
  final String language;
  final Future<void> Function(String?)? select;
  const AchievementsScreen({
    super.key,
    required this.load,
    required this.language,
    this.select,
  });
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<Map<String, dynamic>> result;
  String category = 'all';
  String? selectedId;
  bool saving = false;
  String t(String en, String ru, String lv) =>
      achievementText(widget.language, en, ru, lv);
  @override
  void initState() {
    super.initState();
    result = load();
  }

  Future<Map<String, dynamic>> load() async {
    final data = await widget.load();
    selectedId = data['selectedId'] as String?;
    return data;
  }

  Future<void> select(String? id) async {
    if (saving || widget.select == null) return;
    setState(() => saving = true);
    try {
      await widget.select!(id);
      if (mounted) setState(() => selectedId = id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Could not save achievement',
                'Не удалось сохранить достижение',
                'Neizdevās saglabāt sasniegumu',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> refresh() async {
    final next = load();
    setState(() {
      result = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0F13),
    appBar: AppBar(
      title: Text(t('Achievements', 'Достижения', 'Sasniegumi')),
      actions: [
        IconButton(
          onPressed: saving
              ? null
              : () {
                  refresh().catchError((Object _) {});
                },
          tooltip: t('Refresh', 'Обновить', 'Atjaunot'),
          icon: const Icon(Icons.refresh),
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
                    'Could not load achievements',
                    'Не удалось загрузить достижения',
                    'Neizdevās ielādēt sasniegumus',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    refresh().catchError((Object _) {});
                  },
                  child: Text(t('Retry', 'Повторить', 'Mēģināt vēlreiz')),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        final items = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final groups = <String, String>{'all': t('All', 'Все', 'Visi')};
        for (final item in items) {
          groups[item['category'] as String] = item['category'] == 'tourist'
              ? t('Tourist', 'Турист', 'Ceļotājs')
              : (item['title'] as Map)[widget.language] as String? ??
                    (item['title'] as Map)['en'] as String;
        }
        final visible = items
            .where((e) => category == 'all' || e['category'] == category)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (selectedId != null && widget.select != null)
              TextButton.icon(
                onPressed: saving ? null : () => select(null),
                icon: const Icon(Icons.hide_image_outlined),
                label: Text(
                  t(
                    'Remove from profile',
                    'Убрать из профиля',
                    'Noņemt no profila',
                  ),
                ),
              ),
            if (data['enabled'] != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  t(
                    'Achievement awards are not enabled yet',
                    'Начисление за достижения пока не включено',
                    'Sasniegumu atlīdzības vēl nav ieslēgtas',
                  ),
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              items: groups.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => category = value ?? 'all'),
            ),
            const SizedBox(height: 16),
            for (final item in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AchievementBadge(item: item),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['title'] as Map)[widget.language]
                                    as String? ??
                                (item['title'] as Map)['en'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(achievementRequirement(item, widget.language)),
                          const SizedBox(height: 4),
                          Text(
                            '+${item['xp']} XP',
                            style: const TextStyle(color: Color(0xFF72D8AE)),
                          ),
                          Text(
                            item['status'] == 'confirmed'
                                ? t('Unlocked', 'Получено', 'Iegūts')
                                : item['status'] == 'pending'
                                ? t(
                                    'XP pending',
                                    'XP ожидает начисления',
                                    'XP gaida piešķiršanu',
                                  )
                                : item['status'] == 'revoked'
                                ? t('Revoked', 'Отозвано', 'Atsaukts')
                                : item['available'] != true
                                ? t(
                                    'Not available yet',
                                    'Пока недоступно',
                                    'Vēl nav pieejams',
                                  )
                                : '${item['progress']} / ${item['threshold']}',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          if (widget.select != null &&
                              item['status'] == 'confirmed')
                            TextButton.icon(
                              key: ValueKey('select-${item['id']}'),
                              onPressed: saving || selectedId == item['id']
                                  ? null
                                  : () => select(item['id'] as String),
                              icon: Icon(
                                selectedId == item['id']
                                    ? Icons.check_circle
                                    : Icons.star_outline,
                              ),
                              label: Text(
                                selectedId == item['id']
                                    ? t('On profile', 'В профиле', 'Profilā')
                                    : t(
                                        'Show on profile',
                                        'Выбрать главным',
                                        'Rādīt profilā',
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

String achievementRequirement(Map<String, dynamic> item, String language) {
  String t(String en, String ru, String lv) =>
      achievementText(language, en, ru, lv);
  final n = item['threshold'];
  return switch (item['category']) {
    'spots' => t(
      '$n approved permanent spots',
      '$n одобренных постоянных спотов',
      '$n apstiprinātas pastāvīgas vietas',
    ),
    'visits' => t(
      '$n verified spot visits',
      '$n подтверждённых посещений спотов',
      '$n apstiprināti vietu apmeklējumi',
    ),
    'tourist' => t(
      'Visit a spot within 100 m in this foreign country',
      'Посетить спот в этой иностранной стране в радиусе 100 м',
      'Apmeklēt vietu 100 m rādiusā šajā ārvalstī',
    ),
    'tenure' => t(
      '$n months since registration',
      '$n месяцев с регистрации',
      '$n mēneši kopš reģistrācijas',
    ),
    'moderator' => t(
      '$n months of moderator service',
      '$n месяцев работы модератором',
      '$n mēneši moderatora darbā',
    ),
    'groups' => t(
      'Maintain at least $n group members for one month',
      'Не менее $n участников группы непрерывно в течение месяца',
      'Vismaz $n grupas dalībnieki nepārtraukti vienu mēnesi',
    ),
    'reports' => t(
      '$n reports confirmed by moderation',
      '$n репортов, подтверждённых модерацией',
      '$n moderatoru apstiprināti ziņojumi',
    ),
    'meets' => t(
      'Organize $n meets',
      'Организовать $n митов',
      'Organizēt $n tikšanās',
    ),
    'topics' => t('$n active topics', '$n активных тем', '$n aktīvas tēmas'),
    _ => '$n',
  };
}

class XpProfileActions extends StatelessWidget {
  final String language;
  final VoidCallback onAchievements;
  final VoidCallback onRewards;
  final VoidCallback? onHistory;
  const XpProfileActions({
    super.key,
    required this.language,
    required this.onAchievements,
    required this.onRewards,
    this.onHistory,
  });
  @override
  Widget build(BuildContext context) {
    String t(String en, String ru, String lv) =>
        achievementText(language, en, ru, lv);
    Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        action(
          Icons.workspace_premium_outlined,
          t('Achievements', 'Достижения', 'Sasniegumi'),
          onAchievements,
        ),
        action(
          Icons.card_giftcard,
          t('Rewards', 'Награды', 'Atlīdzības'),
          onRewards,
        ),
        action(Icons.history, t('History', 'История', 'Vēsture'), onHistory),
      ],
    );
  }
}

class XpRewardsScreen extends StatefulWidget {
  final String language;
  final Future<Map<String, dynamic>> Function() load;
  const XpRewardsScreen({
    super.key,
    required this.language,
    required this.load,
  });
  @override
  State<XpRewardsScreen> createState() => _XpRewardsScreenState();
}

class _XpRewardsScreenState extends State<XpRewardsScreen> {
  late Future<Map<String, dynamic>> result;
  String t(String en, String ru, String lv) =>
      achievementText(widget.language, en, ru, lv);
  @override
  void initState() {
    super.initState();
    result = widget.load();
  }

  void refresh() {
    final next = widget.load();
    setState(() {
      result = next;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0F13),
    appBar: AppBar(
      title: Text(t('Rewards', 'Награды', 'Atlīdzības')),
      actions: [
        IconButton(
          onPressed: refresh,
          tooltip: t('Refresh', 'Обновить', 'Atjaunot'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
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
        final items = (snapshot.data!['items'] as List).cast<Map>();
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 28),
          itemBuilder: (context, index) {
            final item = items[index];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    item['category'] == 'profile'
                        ? Icons.person_outline
                        : item['category'] == 'garage_car'
                        ? Icons.directions_car_outlined
                        : Icons.place_outlined,
                    color: const Color(0xFF72D8AE),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['title'] as Map)[widget.language] as String? ??
                            (item['title'] as Map)['en'] as String,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '+${item['xp']} XP · ${item['repeatable'] == true ? t('Per spot', 'За каждый спот', 'Par katru vietu') : t('Once', 'Один раз', 'Vienu reizi')}',
                        style: const TextStyle(color: Color(0xFF72D8AE)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${t('Completed', 'Выполнено', 'Izpildīts')}: ${item['completed']}${item['repeatable'] == true ? '' : ' / 1'} · ${t('Earned', 'Получено', 'Saņemts')}: ${item['earnedXp']} XP',
                      ),
                      if ((item['pending'] as num? ?? 0) > 0)
                        Text(
                          '${t('Pending awards', 'Ожидают начисления', 'Gaida piešķiršanu')}: ${item['pending']}',
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class AchievementBadge extends StatelessWidget {
  final Map<String, dynamic> item;
  const AchievementBadge({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final category = item['category'];
    final tier = (item['tier'] as int? ?? 1).clamp(1, 5);
    const colors = [
      Color(0xFFC98B50),
      Color(0xFFC3CEDB),
      Color(0xFFF3D47B),
      Color(0xFF9CDBFF),
      Color(0xFFAA9AFF),
    ];
    final color = colors[tier - 1];
    final icon = switch (category) {
      'moderator' => Icons.admin_panel_settings_rounded,
      'reports' => Icons.report_outlined,
      'groups' => Icons.groups,
      'meets' => Icons.directions_car,
      'visits' => Icons.route,
      _ => Icons.workspace_premium,
    };
    int? badge;
    if (category == 'tenure') badge = [1, 2, 4, 3][tier.clamp(1, 4) - 1];
    if (category == 'topics') badge = [5, 6, 7, 8][tier.clamp(1, 4) - 1];
    if (category == 'spots') badge = [13, 14, 15, 16][tier.clamp(1, 4) - 1];
    Widget graphic;
    if (category == 'tourist') {
      graphic = ClipPath(
        clipper: _CountryShieldClipper(),
        child: Image.asset(item['asset'] as String, fit: BoxFit.contain),
      );
    } else if (badge != null) {
      graphic = ClipOval(
        child: Transform.scale(
          scale: 1.1,
          child: Image.asset(
            'assets/achievements/badge_$badge.png',
            fit: BoxFit.contain,
          ),
        ),
      );
    } else {
      graphic = Container(
        decoration: category == 'moderator'
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF181A20),
                border: Border.all(color: color, width: 4),
              ),
        child: Icon(
          icon,
          color: color,
          size: category == 'moderator' ? 66 : 40,
        ),
      );
    }
    return SizedBox(
      width: 80,
      height: 88,
      child: Stack(
        children: [
          SizedBox(width: 80, height: 80, child: graphic),
          if (category != 'tourist')
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF161921),
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${item['threshold']}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountryShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * .175, s.height * .08)
    ..lineTo(s.width * .825, s.height * .08)
    ..quadraticBezierTo(
      s.width * .82,
      s.height * .14,
      s.width * .885,
      s.height * .20,
    )
    ..lineTo(s.width * .885, s.height * .42)
    ..quadraticBezierTo(
      s.width * .885,
      s.height * .70,
      s.width * .5,
      s.height * .914,
    )
    ..quadraticBezierTo(
      s.width * .115,
      s.height * .70,
      s.width * .115,
      s.height * .42,
    )
    ..lineTo(s.width * .115, s.height * .20)
    ..quadraticBezierTo(
      s.width * .18,
      s.height * .14,
      s.width * .175,
      s.height * .08,
    )
    ..close();
  @override
  bool shouldReclip(_CountryShieldClipper oldClipper) => false;
}
