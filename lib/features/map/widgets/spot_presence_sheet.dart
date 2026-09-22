import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/app_language.dart'
    show AppLanguage, appUiPreferences;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/auth/data/usernames.dart' show displayUsername;
import 'package:ccs_app/features/map/models/live_location.dart'
    show LiveLocationData;

String spotPeopleLabel(int count) => switch (appUiPreferences.language) {
  AppLanguage.ru => 'Людей рядом: $count',
  AppLanguage.lv => 'Cilvēki tuvumā: $count',
  _ => 'People nearby: $count',
};

class SpotPresenceCount extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const SpotPresenceCount({
    super.key,
    required this.count,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: spotPeopleLabel(count),
    child: Semantics(
      button: true,
      label: spotPeopleLabel(count),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: blue,
            border: Border.all(color: Colors.white70, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
          ),
          padding: const EdgeInsets.all(5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_alt, size: 13, color: Colors.white),
              Expanded(
                child: FittedBox(
                  child: CcsText(
                    count > 999 ? '999+' : '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SpotPeopleSheet extends StatefulWidget {
  final String title;
  final List<LiveLocationData> Function() load;
  final void Function(LiveLocationData) onProfile;
  const SpotPeopleSheet({
    super.key,
    required this.title,
    required this.load,
    required this.onProfile,
  });
  @override
  State<SpotPeopleSheet> createState() => _SpotPeopleSheetState();
}

class _SpotPeopleSheetState extends State<SpotPeopleSheet> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.load();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: CcsText(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: CcsText(spotPeopleLabel(people.length)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: people.length,
                itemBuilder: (context, index) {
                  final person = people[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: CcsText(
                      displayUsername(person.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onProfile(person),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
