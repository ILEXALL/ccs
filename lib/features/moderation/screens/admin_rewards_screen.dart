import 'dart:async';
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
  final ValueChanged<String>? onOpenSpot;
  const AdminRewardsScreen({
    super.key,
    required this.language,
    required this.request,
    this.onOpenSpot,
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
        builder: (_) => _RewardEditor(
          language: widget.language,
          request: widget.request,
          onOpenSpot: widget.onOpenSpot,
        ),
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
          tooltip: t('XP activity', 'Журнал XP', 'XP žurnāls'),
          icon: const Icon(Icons.receipt_long),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminXpActivityScreen(
                language: widget.language,
                request: widget.request,
              ),
            ),
          ),
        ),
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
                'Awarded once per person after a verified 5-minute stay within 100 m during the specified dates. Counts toward the weekly XP limit.',
                'Награда выдаётся один раз каждому за подтверждённые 5 минут в пределах 100 м в указанный срок. Входит в недельный лимит XP.',
                'Piešķir vienreiz par apstiprinātām 5 minūtēm 100 m rādiusā norādītajā laikā. Ietilpst nedēļas XP limitā.',
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
                      TextButton.icon(
                        icon: const Icon(Icons.people_outline),
                        label: Text(t('Recipients', 'Получатели', 'Saņēmēji')),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminXpActivityScreen(
                              language: widget.language,
                              request: widget.request,
                              rewardId: item['id'] as String,
                            ),
                          ),
                        ),
                      ),
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
  final ValueChanged<String>? onOpenSpot;
  const _RewardEditor({
    required this.language,
    required this.request,
    this.onOpenSpot,
  });
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
  int? nextOffset;
  int searchGeneration = 0;
  Timer? searchDebounce;
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
  void initState() {
    super.initState();
    find();
  }

  void searchChanged(String _) {
    searchDebounce?.cancel();
    searchGeneration++;
    searchDebounce = Timer(const Duration(milliseconds: 300), () => find());
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    title.dispose();
    xp.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> find({bool more = false}) async {
    searchDebounce?.cancel();
    final generation = ++searchGeneration;
    final offset = more ? nextOffset : 0;
    if (offset == null) return;
    setState(() {
      searching = true;
      error = null;
      if (!more) {
        targets = [];
        nextOffset = null;
      }
    });
    try {
      final result = await widget.request('admin_reward_targets', {
        'search': search.text,
        'offset': offset,
      });
      if (mounted && generation == searchGeneration) {
        setState(() {
          final items = (result['items'] as List).cast<Map>();
          targets = more ? [...targets, ...items] : items;
          nextOffset = (result['nextOffset'] as num?)?.toInt();
        });
      }
    } catch (_) {
      if (mounted && generation == searchGeneration) {
        setState(() {
          error = t(
            'Could not load places. Retry search.',
            'Не удалось загрузить места. Повтори поиск.',
            'Neizdevās ielādēt vietas. Atkārto meklēšanu.',
          );
        });
      }
    } finally {
      if (mounted && generation == searchGeneration) {
        setState(() => searching = false);
      }
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
              onChanged: searchChanged,
              onSubmitted: (_) => find(),
              decoration: InputDecoration(
                labelText: t(
                  'Search by name',
                  'Поиск по названию',
                  'Meklēt pēc nosaukuma',
                ),
                suffixIcon: IconButton(
                  onPressed: searching ? null : () => find(),
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
                leading: SizedBox(
                  width: 52,
                  height: 52,
                  child:
                      item['photoUrl'] is String &&
                          (item['photoUrl'] as String).startsWith('https://')
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            item['photoUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              item['event'] == true ? Icons.event : Icons.place,
                            ),
                          ),
                        )
                      : Icon(item['event'] == true ? Icons.event : Icons.place),
                ),
                title: Text(item['name'] as String),
                subtitle: Text(
                  [
                    if ((item['cityCountry'] as String? ?? '').isNotEmpty)
                      item['cityCountry'],
                    if (item['lat'] is num && item['lng'] is num)
                      '${(item['lat'] as num).toStringAsFixed(5)}, ${(item['lng'] as num).toStringAsFixed(5)}',
                    'ID: ${item['id']}',
                  ].join('\n'),
                ),
                trailing: widget.onOpenSpot == null
                    ? null
                    : IconButton(
                        tooltip: t('Open spot', 'Открыть спот', 'Atvērt vietu'),
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () =>
                            widget.onOpenSpot!(item['id'] as String),
                      ),
                selected: target?['id'] == item['id'],
                onTap: () => setState(() {
                  target = item;
                }),
              ),
            if (!searching && targets.isEmpty && error == null)
              Text(
                t('No places found', 'Места не найдены', 'Vietas nav atrastas'),
              ),
            if (nextOffset != null)
              TextButton(
                onPressed: searching ? null : () => find(more: true),
                child: Text(t('Show more', 'Показать ещё', 'Rādīt vairāk')),
              ),
            const SizedBox(height: 16),
            Text(
              t(
                'XP is awarded for visits during this period. Dates use your device time zone',
                'XP выдаётся за посещение в этот период. Даты указаны в часовом поясе устройства',
                'XP piešķir par apmeklējumu šajā periodā. Datumi ierīces laika joslā',
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

class AdminXpActivityScreen extends StatefulWidget {
  final String language;
  final RewardRequest request;
  final String? rewardId;
  const AdminXpActivityScreen({
    super.key,
    required this.language,
    required this.request,
    this.rewardId,
  });
  @override
  State<AdminXpActivityScreen> createState() => _AdminXpActivityScreenState();
}

class _AdminXpActivityScreenState extends State<AdminXpActivityScreen> {
  final List<Map> items = [];
  String? cursor;
  bool loading = false;
  bool failed = false;
  String t(String en, String ru, String lv) => widget.language == 'ru'
      ? ru
      : widget.language == 'lv'
      ? lv
      : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      failed = false;
      if (refresh) {
        items.clear();
        cursor = null;
      }
    });
    try {
      final data = await widget.request(
        widget.rewardId == null ? 'admin_xp_audit' : 'admin_reward_recipients',
        {
          if (widget.rewardId != null) 'id': widget.rewardId,
          if (cursor != null) 'cursor': cursor,
        },
      );
      if (mounted)
        setState(() {
          items.addAll((data['items'] as List).cast<Map>());
          cursor = data['nextCursor'] as String?;
        });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String status(Map item) => switch (item['status']) {
    'confirmed' => t('Received', 'Получено', 'Saņemts'),
    'pending' => t('Pending', 'Ожидает начисления', 'Gaida piešķiršanu'),
    'awaiting_payment' => t(
      'Visit confirmed, awaiting XP',
      'Посещение подтверждено, ожидает XP',
      'Apmeklējums apstiprināts, gaida XP',
    ),
    'rejected' => t('Rejected', 'Отклонено', 'Noraidīts'),
    _ => '${item['status']}',
  };
  String title(Map item) {
    final value = item['title'];
    return value is Map
        ? '${value[widget.language] ?? value['en'] ?? item['action']}'
        : '${value ?? ''}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.rewardId == null
            ? t('XP activity', 'Журнал XP', 'XP žurnāls')
            : t(
                'Reward recipients',
                'Получатели награды',
                'Atlīdzības saņēmēji',
              ),
      ),
      actions: [
        IconButton(
          onPressed: loading ? null : () => load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.rewardId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              t(
                'Visit XP: 50 per spot, up to 3 per day and 7 per week. Each visit requires 5 minutes within 100 m. Repeated claims do not award XP again.',
                'За спот — 50 XP: максимум 3 в день и 7 в неделю. Для посещения нужны 5 минут в пределах 100 м. Повторные запросы не дают XP заново.',
                'Par vietu — 50 XP: līdz 3 dienā un 7 nedēļā. Apmeklējumam vajag 5 minūtes 100 m rādiusā. Atkārtoti pieprasījumi nedod papildu XP.',
              ),
            ),
          ),
        for (final item in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${item['username']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'ID: ${item['userId']}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (widget.rewardId == null) Text(title(item)),
                  Text(
                    '${status(item)} · ${item['amount'] ?? item['receivedXp'] ?? 0} XP / ${item['requestedAmount'] ?? item['xp'] ?? 0} XP',
                  ),
                  if (item['reason'] != null) Text('${item['reason']}'),
                  if (item['createdAt'] is num || item['completedAt'] is num)
                    Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(
                        DateTime.fromMillisecondsSinceEpoch(
                          ((item['completedAt'] ?? item['createdAt']) as num)
                              .toInt(),
                        ).toLocal(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (failed)
          TextButton(
            onPressed: () => load(),
            child: Text(
              t(
                'Could not load. Retry',
                'Не удалось загрузить. Повторить',
                'Neizdevās ielādēt. Atkārtot',
              ),
            ),
          ),
        if (!loading && !failed && items.isEmpty)
          Text(t('No records yet', 'Записей пока нет', 'Ierakstu vēl nav')),
        if (!loading && cursor != null)
          TextButton(
            onPressed: () => load(),
            child: Text(t('Show more', 'Показать ещё', 'Rādīt vairāk')),
          ),
      ],
    ),
  );
}
