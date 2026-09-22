import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/notifications/widgets/notification_bell.dart'
    show CcsNotificationBell;
import 'package:ccs_app/features/progression/widgets/leaderboard_action.dart'
    show CcsXpLeaderboardAction;
import 'package:ccs_app/shared/widgets/language_selector.dart'
    show CcsLanguageSelector;

List<Widget> buildAppBarActions({
  bool showXpLeaderboard = false,
  List<Widget> afterXpActions = const <Widget>[],
}) {
  return [
    if (showXpLeaderboard) const CcsXpLeaderboardAction(),
    if (showXpLeaderboard) const SizedBox(width: 2),
    ...afterXpActions,
    const CcsLanguageSelector(),
    const SizedBox(width: 6),
    const CcsNotificationBell(),
    const SizedBox(width: 4),
  ];
}
