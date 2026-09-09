import 'package:flutter/material.dart';

String achievementText(String language, String en, String ru, String lv) =>
    language == 'ru' ? ru : language == 'lv' ? lv : en;

class AchievementsScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() load;
  final String language;
  const AchievementsScreen({super.key, required this.load, required this.language});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<Map<String, dynamic>> result;
  String category = 'all';
  String t(String en, String ru, String lv) => achievementText(widget.language, en, ru, lv);
  @override
  void initState() { super.initState(); result = widget.load(); }
  Future<void> refresh() async {
    final next = widget.load();
    setState(() => result = next);
    await next;
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D0F13),
    appBar: AppBar(title: Text(t('Achievements', 'Достижения', 'Sasniegumi')),
      actions: [IconButton(onPressed: () { refresh().catchError((Object _) {}); },
        tooltip: t('Refresh', 'Обновить', 'Atjaunot'), icon: const Icon(Icons.refresh))]),
    body: FutureBuilder<Map<String, dynamic>>(future: result, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('Could not load achievements', 'Не удалось загрузить достижения', 'Neizdevās ielādēt sasniegumus')),
        TextButton(onPressed: () { refresh().catchError((Object _) {}); },
          child: Text(t('Retry', 'Повторить', 'Mēģināt vēlreiz'))),
      ]));
      }
      final data = snapshot.data!;
      final items = (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final groups = <String, String>{'all': t('All', 'Все', 'Visi')};
      for (final item in items) {
        groups[item['category'] as String] = item['category'] == 'tourist'
          ? t('Tourist', 'Турист', 'Ceļotājs') : (item['title'] as Map)[widget.language] as String? ?? (item['title'] as Map)['en'] as String;
      }
      final visible = items.where((e) => category == 'all' || e['category'] == category).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (data['enabled'] != true) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: Text(t('Achievement awards are not enabled yet', 'Начисление за достижения пока не включено', 'Sasniegumu atlīdzības vēl nav ieslēgtas'))),
        DropdownButtonFormField<String>(initialValue: category, isExpanded: true,
          items: groups.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (value) => setState(() => category = value ?? 'all')),
        const SizedBox(height: 16),
        for (final item in visible) Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, children: [
            AchievementBadge(item: item), const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((item['title'] as Map)[widget.language] as String? ?? (item['title'] as Map)['en'] as String,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(item['unit'] == 'country' ? t('First visit in this country', 'Первое посещение в этой стране', 'Pirmais apmeklējums šajā valstī')
                : '${item['threshold']} ${item['unit'] == 'months' ? t('months', 'мес.', 'mēn.') : item['unit'] == 'members_month' ? t('members for one month', 'участников в течение месяца', 'dalībnieki vienu mēnesi') : t('completed', 'выполнено', 'paveikts')}'),
              const SizedBox(height: 4),
              Text('+${item['xp']} XP', style: const TextStyle(color: Color(0xFF72D8AE))),
              Text(item['status'] == 'confirmed' ? t('Unlocked', 'Получено', 'Iegūts')
                : item['status'] == 'pending' ? t('XP pending', 'XP ожидает начисления', 'XP gaida piešķiršanu')
                : item['status'] == 'revoked' ? t('Revoked', 'Отозвано', 'Atsaukts')
                : item['available'] != true ? t('Not available yet', 'Пока недоступно', 'Vēl nav pieejams')
                : '${item['progress']} / ${item['threshold']}', style: const TextStyle(color: Colors.white60)),
            ])),
          ],
        )),
      ]);
    }),
  );
}

class AchievementBadge extends StatelessWidget {
  final Map<String, dynamic> item;
  const AchievementBadge({super.key, required this.item});
  @override
  Widget build(BuildContext context) {
    final category = item['category'];
    final tier = (item['tier'] as int? ?? 1).clamp(1, 5);
    const colors = [Color(0xFFC98B50), Color(0xFFC3CEDB), Color(0xFFF3D47B), Color(0xFF9CDBFF), Color(0xFFAA9AFF)];
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
    if (category == 'tenure') badge = [1,2,4,3][tier.clamp(1,4)-1];
    if (category == 'topics') badge = [5,6,7,8][tier.clamp(1,4)-1];
    if (category == 'spots') badge = [13,14,15,16][tier.clamp(1,4)-1];
    Widget graphic;
    if (category == 'tourist') {
      graphic = ClipPath(clipper: _CountryShieldClipper(), child: Image.asset(item['asset'] as String, fit: BoxFit.contain));
    } else if (badge != null) {
      graphic = ClipOval(child: Transform.scale(scale: 1.1,
        child: Image.asset('assets/achievements/badge_$badge.png', fit: BoxFit.contain)));
    } else {
      graphic = Container(decoration: category == 'moderator' ? null : BoxDecoration(
        shape: BoxShape.circle, color: const Color(0xFF181A20),
        border: Border.all(color: color, width: 4)),
        child: Icon(icon, color: color, size: category == 'moderator' ? 66 : 40));
    }
    return SizedBox(width: 80, height: 88, child: Stack(children: [
      SizedBox(width: 80, height: 80, child: graphic),
      if (category != 'tourist') Positioned(bottom: 0, right: 0, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFF161921), border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
        child: Text('${item['threshold']}', style: TextStyle(color: color, fontWeight: FontWeight.bold)))),
    ]));
  }
}

class _CountryShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(s.width * .175, s.height * .08)
    ..lineTo(s.width * .825, s.height * .08)
    ..quadraticBezierTo(s.width * .82, s.height * .14, s.width * .885, s.height * .20)
    ..lineTo(s.width * .885, s.height * .42)
    ..quadraticBezierTo(s.width * .885, s.height * .70, s.width * .5, s.height * .914)
    ..quadraticBezierTo(s.width * .115, s.height * .70, s.width * .115, s.height * .42)
    ..lineTo(s.width * .115, s.height * .20)
    ..quadraticBezierTo(s.width * .18, s.height * .14, s.width * .175, s.height * .08)
    ..close();
  @override
  bool shouldReclip(_CountryShieldClipper oldClipper) => false;
}
