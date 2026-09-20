import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

typedef RewardRequest =
    Future<Map<String, dynamic>> Function(
      String action, [
      Map<String, dynamic> extra,
    ]);

class AdminRewardsScreen extends StatefulWidget {
  final String language;
  final RewardRequest request;
  const AdminRewardsScreen({
    super.key,
    required this.language,
    required this.request,
  });
  @override
  State<AdminRewardsScreen> createState() => _AdminRewardsScreenState();
}

class _AdminRewardsScreenState extends State<AdminRewardsScreen> {
  late Future<Map<String, dynamic>> data;
  String t(String en, String ru, String lv) => widget.language == 'ru'
      ? ru
      : widget.language == 'lv'
      ? lv
      : en;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    data = widget.request('admin_rewards');
  }

  Future<void> create() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _RewardEditor(language: widget.language, request: widget.request),
      ),
    );
    if (added == true && mounted) setState(reload);
  }

  Future<void> cancel(Map item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t('Stop this reward?', 'Остановить награду?', 'Apturēt atlīdzību?'),
        ),
        content: Text(
          t(
            'Already earned rewards are preserved.',
            'Уже заработанные награды сохранятся.',
            'Jau nopelnītās atlīdzības saglabāsies.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Back', 'Назад', 'Atpakaļ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Stop', 'Остановить', 'Apturēt')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.request('admin_reward_cancel', {'id': item['id']});
      if (mounted) setState(reload);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Could not stop reward',
                'Не удалось остановить награду',
                'Neizdevās apturēt atlīdzību',
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('Rewards', 'Награды', 'Atlīdzības')),
      actions: [
        IconButton(
          onPressed: () => setState(reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.add),
      label: Text(t('Add reward', 'Добавить награду', 'Pievienot atlīdzību')),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: () => setState(reload),
              child: Text(
                t(
                  'Admin access required, or loading failed. Retry',
                  'Нужны права администратора или произошла ошибка. Повторить',
                  'Vajadzīgas administratora tiesības vai ielāde neizdevās. Atkārtot',
                ),
              ),
            ),
          );
        final items = (snapshot.data?['items'] as List? ?? []).cast<Map>();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text(
              t(
                'Bonus tasks from admins',
                'Дополнительные задания от администраторов',
                'Administratoru papildu uzdevumi',
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Awarded once per person after a verified visit during the specified dates. Counts toward the weekly XP limit.',
                'Награда выдаётся один раз каждому за подтверждённое посещение в указанный срок. Входит в недельный лимит XP.',
                'Piešķir vienreiz par apstiprinātu apmeklējumu norādītajā laikā. Ietilpst nedēļas XP limitā.',
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Text(
                t(
                  'No custom rewards yet',
                  'Своих наград пока нет',
                  'Papildu atlīdzību vēl nav',
                ),
              ),
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['title'] as Map)[widget.language] as String? ??
                            (item['title'] as Map)['en'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('${item['spotName']} · +${item['xp']} XP'),
                      Text(
                        '${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['startsAt'] as num).toInt()).toLocal())} → ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['endsAt'] as num).toInt()).toLocal())}',
                      ),
                      Text(
                        item['enabled'] != true
                            ? t('Stopped', 'Остановлено', 'Apturēts')
                            : (item['endsAt'] as num) <=
                                  DateTime.now().millisecondsSinceEpoch
                            ? t('Ended', 'Завершено', 'Beidzies')
                            : (item['startsAt'] as num) >
                                  DateTime.now().millisecondsSinceEpoch
                            ? t('Scheduled', 'Запланировано', 'Ieplānots')
                            : t('Active', 'Активно', 'Aktīvs'),
                      ),
                      if (item['enabled'] == true &&
                          (item['endsAt'] as num) >
                              DateTime.now().millisecondsSinceEpoch)
                        TextButton(
                          onPressed: () => cancel(item),
                          child: Text(
                            t(
                              'Stop reward',
                              'Остановить награду',
                              'Apturēt atlīdzību',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _RewardEditor extends StatefulWidget {
  final String language;
  final RewardRequest request;
  const _RewardEditor({required this.language, required this.request});
  @override
  State<_RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends State<_RewardEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final xp = TextEditingController(text: '200');
  final search = TextEditingController();
  final id = const Uuid().v4();
  Map? target;
  List<Map> targets = [];
  DateTime start = DateTime.now();
  late DateTime end = start.add(const Duration(days: 7));
  bool saving = false, searching = false;
  String? error;
  String t(String en, String ru, String lv) => widget.language == 'ru'
      ? ru
      : widget.language == 'lv'
      ? lv
      : en;
  @override
  void dispose() {
    title.dispose();
    xp.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> find() async {
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final result = await widget.request('admin_reward_targets', {
        'search': search.text,
      });
      if (mounted)
        setState(() {
          targets = (result['items'] as List).cast<Map>();
        });
    } catch (_) {
      if (mounted)
        setState(() {
          error = t('Search failed', 'Поиск не удался', 'Meklēšana neizdevās');
        });
    } finally {
      if (mounted)
        setState(() {
          searching = false;
        });
    }
  }

  Future<void> date(bool beginning) async {
    final value = beginning ? start : end;
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !mounted) return;
    setState(() {
      final result = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
      if (beginning) {
        start = result;
      } else {
        end = result;
      }
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (target == null || !end.isAfter(start) || !end.isAfter(DateTime.now())) {
      setState(() {
        error = t(
          'Choose a target and valid dates',
          'Выбери место и корректные даты',
          'Izvēlies vietu un derīgus datumus',
        );
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.request('admin_reward_create', {
        'id': id,
        'spotId': target!['id'],
        'title': {
          for (final lang in ['en', 'ru', 'lv']) lang: title.text.trim(),
        },
        'xp': int.parse(xp.text),
        'startsAt': start.millisecondsSinceEpoch,
        'endsAt': end.millisecondsSinceEpoch,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          error = t(
            'Could not save. Check access, dates and target; retry.',
            'Не удалось сохранить. Проверь права, даты и место; повтори.',
            'Neizdevās saglabāt. Pārbaudi tiesības, datumus un vietu; mēģini vēlreiz.',
          );
        });
    } finally {
      if (mounted)
        setState(() {
          saving = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('New reward', 'Новая награда', 'Jauna atlīdzība')),
    ),
    body: AbsorbPointer(
      absorbing: saving,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: title,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: t(
                  'Task title',
                  'Название задания',
                  'Uzdevuma nosaukums',
                ),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? t('Required', 'Обязательное поле', 'Obligāts lauks')
                  : null,
            ),
            TextFormField(
              controller: xp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'XP (1–3000)'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 3000 ? '1–3000 XP' : null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              t(
                'Visit a specific spot or event',
                'Посетить конкретный спот или мит',
                'Apmeklēt konkrētu vietu vai pasākumu',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextField(
              controller: search,
              onSubmitted: (_) => find(),
              decoration: InputDecoration(
                labelText: t(
                  'Search by name',
                  'Поиск по названию',
                  'Meklēt pēc nosaukuma',
                ),
                suffixIcon: IconButton(
                  onPressed: searching ? null : find,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            if (searching) const LinearProgressIndicator(),
            if (target != null)
              ListTile(
                leading: const Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                ),
                title: Text(target!['name'] as String),
              ),
            for (final item in targets)
              ListTile(
                leading: Icon(
                  item['event'] == true ? Icons.event : Icons.place,
                ),
                title: Text(item['name'] as String),
                selected: target?['id'] == item['id'],
                onTap: () => setState(() {
                  target = item;
                  targets = [];
                }),
              ),
            const SizedBox(height: 16),
            Text(
              t(
                'Dates use your device time zone',
                'Даты указаны в часовом поясе устройства',
                'Datumi ierīces laika joslā',
              ),
            ),
            ListTile(
              title: Text(t('Starts', 'Начало', 'Sākums')),
              subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(start)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => date(true),
            ),
            ListTile(
              title: Text(t('Ends', 'Окончание', 'Beigas')),
              subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(end)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () => date(false),
            ),
            Text(
              t(
                'Once per person. Already earned XP is preserved if the reward is stopped. Title is shown as entered in all app languages.',
                'Один раз на человека. При остановке заработанный XP сохраняется. Название показывается без перевода на всех языках приложения.',
                'Vienreiz katram. Apturot atlīdzību, nopelnītais XP saglabājas. Nosaukums visās valodās redzams bez tulkojuma.',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.add),
              label: Text(
                saving
                    ? t('Saving…', 'Сохранение…', 'Saglabā…')
                    : t(
                        'Create reward',
                        'Создать награду',
                        'Izveidot atlīdzību',
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
