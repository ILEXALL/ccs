import 'package:flutter/widgets.dart';

// Bound by app composition before any screen is mounted.
typedef AppBarActionsBuilder =
    List<Widget> Function({
      bool showXpLeaderboard,
      List<Widget> afterXpActions,
    });
late AppBarActionsBuilder appBarActionsBuilder;
List<Widget> ccsAppBarActions({
  bool showXpLeaderboard = false,
  List<Widget> afterXpActions = const [],
}) => appBarActionsBuilder(
  showXpLeaderboard: showXpLeaderboard,
  afterXpActions: afterXpActions,
);
