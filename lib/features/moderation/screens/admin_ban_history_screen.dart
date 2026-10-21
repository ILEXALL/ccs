import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/moderation/data/moderation_api.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart';

class AdminBanHistoryScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(Map<String, Object?>) request;
  const AdminBanHistoryScreen({super.key, this.request = sendModerationAction});

  @override
  State<AdminBanHistoryScreen> createState() => _AdminBanHistoryScreenState();
}

class _AdminBanHistoryScreenState extends State<AdminBanHistoryScreen> {
  final _entries = <Map<String, dynamic>>[];
  String? _cursor;
  String? _error;
  bool _loading = false;
  bool _previous = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    // Expired bans move between lists even while this screen remains open.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.request({
        'action': 'list_bans',
        'cursor': reset ? null : _cursor,
      });
      if (!mounted) return;
      setState(() {
        if (reset) _entries.clear();
        for (final entry in (result['entries'] as List? ?? [])) {
          final data = Map<String, dynamic>.from(entry as Map);
          _entries.removeWhere((e) => e['uid'] == data['uid']);
          _entries.add(data);
        }
        _cursor = result['cursor'] as String?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _active(Map<String, dynamic> entry) =>
      entry['active'] == true &&
      (entry['expiresAt'] == null ||
          (entry['expiresAt'] as num) > DateTime.now().millisecondsSinceEpoch);

  String _date(dynamic value) {
    if (value is! num) return 'Not recorded';
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _unban(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const CcsText('Remove ban?'),
        content: CcsText(
          'Remove the ban for @${entry['username']}? The ban history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const CcsText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const CcsText('Remove ban'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.request({
        'action': 'unban_user',
        'targetUserId': entry['uid'],
      });
      if (mounted) await _load(reset: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _entries
        .where((entry) => _active(entry) != _previous)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const CcsText('User bans')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const CcsText('Banned app users'),
                  selected: !_previous,
                  onSelected: (_) => setState(() => _previous = false),
                ),
                ChoiceChip(
                  label: const CcsText('Previously banned list'),
                  selected: _previous,
                  onSelected: (_) => setState(() => _previous = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const CcsText(
              'Recorded ban history • dates shown in your local time. Older bans may not have complete records.',
              style: TextStyle(color: Colors.white60),
            ),
            if (_error != null) ...[
              CcsText(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
              TextButton(
                onPressed: () => _load(reset: true),
                child: const CcsText('Retry'),
              ),
            ],
            if (visible.isEmpty && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: CcsText(
                  _cursor == null
                      ? 'No users in this list.'
                      : 'No matching users on loaded pages. Load more to continue.',
                ),
              ),
            for (final entry in visible) _card(entry),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_cursor != null && !_loading)
              TextButton(onPressed: _load, child: const CcsText('Load more')),
          ],
        ),
      ),
    );
  }

  String _banIssuer(Map<String, dynamic> ban) {
    final username = (ban['bannedBy'] as String? ?? '').trim();
    if (username.isNotEmpty) {
      return '@${username.replaceFirst(RegExp(r'^@'), '')}';
    }
    final uid = (ban['bannedByUid'] as String? ?? '').trim();
    return uid.isNotEmpty ? 'Account $uid' : 'Not recorded';
  }

  Widget _card(Map<String, dynamic> entry) {
    final history = (entry['history'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              onPressed: () => openUserProfile(
                context,
                uid: entry['uid'] as String,
                fallbackUsername: entry['username'] as String,
              ),
              child: CcsText('@${entry['username']} • ${entry['country']}'),
            ),
            CcsText(
              'Recorded bans: ${history.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final ban in history) ...[
              const Divider(height: 24),
              CcsText('Banned: ${_date(ban['bannedAt'])}'),
              CcsText('Banned by: ${_banIssuer(ban)}'),
              CcsText(
                '${ban['expiresAt'] != null && (ban['expiresAt'] as num) <= DateTime.now().millisecondsSinceEpoch ? 'Expired' : 'Scheduled expiry'}: ${_date(ban['expiresAt'])}',
              ),
              if (ban['liftedAt'] != null)
                CcsText('Ban removed: ${_date(ban['liftedAt'])}'),
              const SizedBox(height: 6),
              CcsText(
                'Reason: ${(ban['reason'] as String).isEmpty ? 'Not recorded' : ban['reason']}',
              ),
            ],
            if (_active(entry) && entry['canUnban'] == true)
              TextButton.icon(
                onPressed: () => _unban(entry),
                icon: const Icon(Icons.lock_open),
                label: const CcsText('Remove ban'),
              ),
          ],
        ),
      ),
    );
  }
}
