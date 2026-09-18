import 'package:flutter/material.dart';
import 'weekly_rewards_section.dart';
import 'achievement_emblem.dart';
export 'achievement_emblem.dart' show achievementCategoryLabel;

String achievementText(String language, String en, String ru, String lv) =>
    language == 'ru'
    ? ru
    : language == 'lv'
    ? lv
    : en;

class AchievementsScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() load;
  final String language;
  final bool isModerator;
  const AchievementsScreen({
    super.key,
    required this.load,
    required this.language,
    this.isModerator = false,
  });
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
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

  String title(Map<String, dynamic> item) =>
      (item['title'] as Map)[widget.language] as String? ??
      (item['title'] as Map)['en'] as String;

  String status(Map<String, dynamic> item) {
    if (item['status'] == 'confirmed') {
      return t('Unlocked', 'Получено', 'Iegūts');
    }
    if (item['status'] == 'revoked') {
      return t('Revoked', 'Отозвано', 'Atsaukts');
    }
    if (item['status'] == 'pending') {
      return t('Pending', 'Ожидает начисления', 'Gaida piešķiršanu');
    }
    if (item['status'] == 'blocked') {
      return t('Blocked', 'Заблокировано', 'Bloķēts');
    }
    if (item['available'] != true) {
      return t('Not available yet', 'Пока недоступно', 'Vēl nav pieejams');
    }
    return '${item['progress'] ?? 0} / ${item['threshold']}';
  }

  void showDetails(Map<String, dynamic> item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171A20),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AchievementBadge(item: item),
              const SizedBox(height: 12),
              Text(
                title(item),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                achievementRequirement(item, widget.language),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '+${item['xp']} XP',
                style: const TextStyle(
                  color: Color(0xFF72D8AE),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(status(item), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Close', 'Закрыть', 'Aizvērt')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0F13),
    appBar: AppBar(
      title: Text(t('Achievements', 'Достижения', 'Sasniegumi')),
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
                  onPressed: refresh,
                  child: Text(t('Retry', 'Повторить', 'Mēģināt vēlreiz')),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        final isModerator = data['isModerator'] == true ||
            (data['isModerator'] == null && widget.isModerator);
        final items = (data['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            // Also hide the retired category when an older backend responds.
            .where((item) => item['category'] != 'reports' &&
                (item['category'] != 'moderator' || isModerator))
            .toList();
        final main = items
            .where((item) => item['category'] != 'tourist')
            .toList();
        final countries = items
            .where((item) => item['category'] == 'tourist')
            .toList();
        final unlocked = items
            .where((item) => item['status'] == 'confirmed')
            .length;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '$unlocked / ${items.length} ${t('Unlocked', 'Получено', 'Iegūts')}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  t(
                    'No unlocked achievements yet',
                    'Пока нет полученных достижений',
                    'Vēl nav iegūtu sasniegumu',
                  ),
                  textAlign: TextAlign.center,
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
            ]))),
            if (main.isNotEmpty)
              ...section(
                'main',
                t(
                  'Main achievements',
                  'Основные достижения',
                  'Pamata sasniegumi',
                ),
                main,
              ),
            if (countries.isNotEmpty)
              ...section(
                'countries',
                t('Countries', 'Страны', 'Valstis'),
                countries,
              ),
          ],
        );
      },
    ),
  );

  List<Widget> section(String id, String heading, List<Map<String, dynamic>> items) => [
    SliverToBoxAdapter(child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Text(heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    )),
    SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverLayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final columns = ((constraints.crossAxisExtent + 6) / (60 * scale.clamp(1, 3))).floor().clamp(1, 6);
        return SliverGrid(
          key: ValueKey('achievement-board-$id'),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns, crossAxisSpacing: 6, mainAxisSpacing: 8,
            mainAxisExtent: 60 + 48 * scale.clamp(1, 10)),
          delegate: SliverChildBuilderDelegate((context, index) => achievementTile(items[index]),
            childCount: items.length),
        );
      }),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 16)),
  ];

  Widget achievementTile(Map<String, dynamic> item) {
    final earned = item['status'] == 'confirmed';
    final color = earned
        ? achievementTierColors[((item['tier'] as int? ?? 1) - 1).clamp(0, 4)]
        : Colors.white38;
    final label = item['category'] == 'tourist'
        ? title(item)
        : achievementCategoryLabel(item['category'] as String, widget.language);
    return Semantics(
      label:
          '${title(item)}. ${achievementRequirement(item, widget.language)}. ${status(item)}. +${item['xp']} XP',
      button: true,
      onTap: () => showDetails(item),
      excludeSemantics: true,
      child: Material(
        key: ValueKey('achievement-tile-${item['id']}'),
        color: earned ? color.withValues(alpha: .09) : const Color(0xFF171A20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: earned ? .65 : .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDetails(item),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FittedBox(child: AchievementBadge(item: item)),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: earned ? Colors.white : Colors.white54,
                      ),
                    ),
                  ),
                ),
                Text(
                  '+${item['xp']} XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      'Visit $n different spots',
      'Посетить $n разных спотов',
      'Apmeklēt $n dažādas vietas',
    ),
    'tourist' => t(
      'Visit this country with location access enabled',
      'Посетить эту страну с разрешённым доступом к геолокации',
      'Apmeklēt šo valsti ar ieslēgtu piekļuvi atrašanās vietai',
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
      '$n approved temporary spots',
      '$n одобренных временных спотов',
      '$n apstiprinātas pagaidu vietas',
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
          itemCount: items.length + 2,
          separatorBuilder: (_, _) => const Divider(height: 28),
          itemBuilder: (context, index) {
            if (index == 0)
              return WeeklyRewardsSection(
                language: widget.language,
                weekly: snapshot.data?['weekly'] as Map?,
              );
            if (index == 1)
              return Text(
                t(
                  'Regular rewards',
                  'Обычные начисления',
                  'Parastās atlīdzības',
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              );
            final item = items[index - 2];
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
    final badge = buildBadge();
    if (item['status'] == 'confirmed') return badge;
    return Opacity(
      opacity: .45,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          .2126,
          .7152,
          .0722,
          0,
          0,
          .2126,
          .7152,
          .0722,
          0,
          0,
          .2126,
          .7152,
          .0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: badge,
      ),
    );
  }

  Widget buildBadge() {
    if (item['category'] != 'tourist') return AchievementEmblem(item: item);
    return SizedBox(
      width: 88,
      height: 96,
      child: ClipPath(
        clipper: _CountryShieldClipper(),
        child: Image.asset(item['asset'] as String, fit: BoxFit.contain),
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
