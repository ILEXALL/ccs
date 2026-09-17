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
        final visible = items;
        final unlocked = items
            .where((item) => item['status'] == 'confirmed')
            .length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '$unlocked / ${items.length} ${t('Unlocked', 'Получено', 'Iegūts')}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (visible.isEmpty)
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
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 180).floor().clamp(
                  2,
                  6,
                );
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                return GridView.builder(
                  key: const ValueKey('achievement-board'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 300 + 260 * (scale - 1).clamp(0, 10),
                  ),
                  itemBuilder: (context, index) =>
                      achievementTile(visible[index]),
                );
              },
            ),
          ],
        );
      },
    ),
  );
  Widget achievementTile(Map<String, dynamic> item) {
    final earned = item['status'] == 'confirmed';
    final color = earned
        ? achievementTierColors[((item['tier'] as int? ?? 1) - 1).clamp(0, 4)]
        : Colors.white38;
    final title =
        (item['title'] as Map)[widget.language] as String? ??
        (item['title'] as Map)['en'] as String;
    final status = earned
        ? t('Unlocked', 'Получено', 'Iegūts')
        : item['status'] == 'revoked'
        ? t('Revoked', 'Отозвано', 'Atsaukts')
        : item['available'] != true
        ? t('Not available yet', 'Пока недоступно', 'Vēl nav pieejams')
        : '${item['progress'] ?? 0} / ${item['threshold']}';
    return Semantics(
      label: '$title. $status',
      child: Container(
        key: ValueKey('achievement-tile-${item['id']}'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: earned
              ? color.withValues(alpha: .09)
              : const Color(0xFF171A20),
          border: Border.all(color: color.withValues(alpha: earned ? .65 : .2)),
          boxShadow: earned
              ? [BoxShadow(color: color.withValues(alpha: .12), blurRadius: 12)]
              : [],
        ),
        child: Column(
          children: [
            AchievementBadge(item: item),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: earned ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: achievementRequirement(item, widget.language),
              child: Text(
                achievementRequirement(item, widget.language),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
            const Spacer(),
            Text(
              '+${item['xp']} XP',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color),
            ),
            if (widget.select != null && earned)
              TextButton(
                key: ValueKey('select-${item['id']}'),
                onPressed: saving || selectedId == item['id']
                    ? null
                    : () => select(item['id'] as String),
                child: Text(
                  selectedId == item['id']
                      ? t('On profile', 'В профиле', 'Profilā')
                      : t(
                          'Show on profile',
                          'Выбрать главным',
                          'Rādīt profilā',
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              )
            else if (!earned)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Colors.white30,
                ),
              ),
          ],
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
