import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/progression/screens/achievements_screen.dart';
import 'package:ccs_app/shared/widgets/app_bar_actions.dart'
    show ccsAppBarActions;
import 'package:ccs_app/core/localization/app_language.dart'
    show appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, currentUserHomeCountryCode, currentUserProfileRevision;
import 'package:ccs_app/features/progression/data/leaderboard.dart'
    show
        XpLeaderboardPageExpired,
        XpLeaderboardPageLoader,
        XpLeaderboardPeriod,
        loadXpLeaderboardEntries,
        xpLeaderboardEmptyTitle,
        xpLeaderboardTitle;
import 'package:ccs_app/features/progression/models/leaderboard_entry.dart'
    show XpLeaderboardEntry;
import 'package:ccs_app/features/progression/widgets/leaderboard_widgets.dart'
    show XpLeaderboardPeriodSelector, XpLeaderboardTile;
import 'package:ccs_app/shared/models/countries.dart' show localizedCountryName;

class XpLeaderboardScreen extends StatefulWidget {
  final bool embedded;
  final XpLeaderboardPageLoader? loadPage;
  const XpLeaderboardScreen({super.key, this.embedded = false, this.loadPage});

  @override
  State<XpLeaderboardScreen> createState() => _XpLeaderboardScreenState();
}

class _XpLeaderboardScreenState extends State<XpLeaderboardScreen>
    with AutomaticKeepAliveClientMixin, LanguageReactiveState {
  @override
  bool get wantKeepAlive => true;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _entries = <XpLeaderboardEntry>[];
  Map<String, dynamic>? _cursor;
  Timer? _debounce;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;
  bool _expired = false;
  String _search = '';
  String _rankingCountry = currentUserHomeCountryCode();
  void _countryChanged() {
    final country = currentUserHomeCountryCode();
    if (!mounted || country == _rankingCountry) return;
    _rankingCountry = country;
    unawaited(_load(reset: true));
  }

  XpLeaderboardPeriod selectedPeriod = XpLeaderboardPeriod.allTime;

  String t(String en, String ru, String lv) =>
      achievementText(appUiPreferences.language.name, en, ru, lv);

  @override
  void initState() {
    super.initState();
    currentUserProfileRevision.addListener(_countryChanged);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    currentUserProfileRevision.removeListener(_countryChanged);
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _cursor == null)) return;
    if (reset) {
      _debounce?.cancel();
      _generation++;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    }
    final generation = _generation;
    final period = selectedPeriod;
    final search = _search;
    setState(() {
      _loading = true;
      _failed = false;
      _expired = false;
      if (reset) {
        _entries.clear();
        _cursor = null;
      }
    });
    try {
      final page = await (widget.loadPage ?? loadXpLeaderboardEntries)(
        period: period,
        search: search,
        cursor: reset ? null : _cursor,
      ).timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _entries.map((entry) => entry.userId).toSet();
        _entries.addAll(page.entries.where((entry) => ids.add(entry.userId)));
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _expired = error is XpLeaderboardPageExpired;
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _searchChanged(String value) {
    final search = value
        .trim()
        .replaceFirst(RegExp(r'^@'), '')
        .trim()
        .toLowerCase();
    if (search == _search) {
      setState(() {});
      return;
    }
    _debounce?.cancel();
    // Invalidate the current request immediately, before the debounce expires.
    _generation++;
    final canLoad = search.isEmpty || search.runes.length >= 2;
    setState(() {
      _search = search;
      _entries.clear();
      _cursor = null;
      _failed = false;
      _loading = canLoad;
    });
    if (!canLoad) return;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  void selectPeriod(XpLeaderboardPeriod period) {
    if (period == selectedPeriod) return;
    setState(() => selectedPeriod = period);
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: CcsText(t('Ranking', 'Рейтинг', 'Reitings')),
              backgroundColor: Colors.transparent,
              foregroundColor: blue,
              actions: ccsAppBarActions(showXpLeaderboard: false),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('ranking-search'),
                  controller: _searchController,
                  onChanged: _searchChanged,
                  maxLength: 31,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (_search.isEmpty || _search.runes.length >= 2) {
                      unawaited(_load(reset: true));
                    }
                  },
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: t(
                      'Search by nickname',
                      'Поиск по нику',
                      'Meklēt pēc lietotājvārda',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: t(
                              'Clear search',
                              'Очистить поиск',
                              'Notīrīt meklēšanu',
                            ),
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _searchChanged('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                XpLeaderboardPeriodSelector(
                  selectedPeriod: selectedPeriod,
                  onChanged: selectPeriod,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: blue,
              backgroundColor: panelGlass,
              onRefresh: () => _load(reset: true),
              child: ListView(
                key: const ValueKey('ranking-list'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  CcsText(
                    _search.isEmpty
                        ? xpLeaderboardTitle(selectedPeriod)
                        : t(
                            'Search results',
                            'Результаты поиска',
                            'Meklēšanas rezultāti',
                          ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CcsText(
                    t(
                      '${localizedCountryName(currentUser.country)} • ${trText('This leaderboard shows public profiles only.')}',
                      'В рейтинге показаны только открытые профили.',
                      'Reitingā redzami tikai publiski profili.',
                    ),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_search.isNotEmpty && _search.runes.length < 2)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: CcsText(
                        t(
                          'Type at least 2 characters to search.',
                          'Введите минимум 2 символа для поиска.',
                          'Ievadiet vismaz 2 rakstzīmes, lai meklētu.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    for (final entry in _entries)
                      XpLeaderboardTile(
                        key: ValueKey('ranking-user-${entry.userId}'),
                        entry: entry,
                        period: selectedPeriod,
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_failed) ...[
                      CcsText(
                        _expired
                            ? t(
                                'Ranking changed. Refresh to continue.',
                                'Рейтинг изменился. Обновите список.',
                                'Reitings ir mainījies. Atjaunojiet sarakstu.',
                              )
                            : t(
                                'Could not load ranking.',
                                'Не удалось загрузить рейтинг.',
                                'Neizdevās ielādēt reitingu.',
                              ),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const ValueKey('ranking-retry'),
                        onPressed: () =>
                            _load(reset: _expired || _entries.isEmpty),
                        child: CcsText(
                          _expired
                              ? t('Refresh', 'Обновить', 'Atjaunot')
                              : t('Retry', 'Повторить', 'Mēģināt vēlreiz'),
                        ),
                      ),
                    ] else if (_entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: CcsText(
                          _search.isEmpty
                              ? xpLeaderboardEmptyTitle(selectedPeriod)
                              : t(
                                  'No matching users in this ranking.',
                                  'В этом рейтинге никого не найдено.',
                                  'Šajā reitingā lietotāji nav atrasti.',
                                ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (_cursor != null)
                      TextButton(
                        key: const ValueKey('ranking-load-more'),
                        onPressed: () => _load(),
                        child: CcsText(
                          t('Show more', 'Показать ещё', 'Rādīt vairāk'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
