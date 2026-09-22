import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/features/community/forum/screens/new_forum_topic.dart'
    show NewForumTopicPage;

Future<void> showCreateTopicDialog(
  BuildContext parentContext, {
  String? initialCategory,
}) async {
  await Navigator.push(
    parentContext,
    appPageRoute(
      builder: (_) => NewForumTopicPage(initialCategory: initialCategory),
    ),
  );
}
