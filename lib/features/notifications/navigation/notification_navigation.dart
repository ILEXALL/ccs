import 'package:flutter/widgets.dart';
import 'package:ccs_app/features/notifications/models/notification_item.dart';

// Bound by app composition before any screen is mounted.
typedef NotificationNavigation =
    Future<void> Function(BuildContext context, NotificationCenterItem item);
late NotificationNavigation notificationNavigation;
Future<void> openNotificationCenterItem(
  BuildContext context,
  NotificationCenterItem item,
) => notificationNavigation(context, item);
