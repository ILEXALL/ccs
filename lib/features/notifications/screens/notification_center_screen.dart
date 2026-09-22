import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/notifications/navigation/notification_navigation.dart'
    show openNotificationCenterItem;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/notifications/data/badge_state.dart'
    show notificationCenterUnreadCount, notificationCenterUnreadCountsBySource;
import 'package:ccs_app/features/notifications/data/notification_formatting.dart'
    show
        notificationCenterColor,
        notificationCenterDisplayBody,
        notificationCenterDisplayTitle,
        notificationCenterIcon,
        notificationCenterTime;
import 'package:ccs_app/features/notifications/data/notification_repository.dart'
    show
        clearNotificationCenterItems,
        loadNotificationCenterItems,
        markNotificationCenterItemsRead;
import 'package:ccs_app/features/notifications/models/notification_item.dart'
    show NotificationCenterItem;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen>
    with LanguageReactiveState {
  late Future<List<NotificationCenterItem>> itemsFuture;
  bool markedRead = false;
  bool clearingNotifications = false;

  @override
  void initState() {
    super.initState();
    itemsFuture = loadNotificationCenterItems();
  }

  void refresh() {
    setState(() {
      markedRead = false;
      itemsFuture = loadNotificationCenterItems();
    });
  }

  Future<void> clearAllNotifications() async {
    if (clearingNotifications) {
      return;
    }

    setState(() => clearingNotifications = true);

    try {
      final items = await itemsFuture;
      await clearNotificationCenterItems(items);
      if (!mounted) {
        return;
      }
      setState(() {
        markedRead = true;
        itemsFuture = Future.value(const <NotificationCenterItem>[]);
      });
    } catch (error, stack) {
      debugPrint('Notification center could not clear items: $error');
      debugPrint('$stack');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Could not clear notifications: $error',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => clearingNotifications = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('Notifications'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          TextButton.icon(
            onPressed: clearingNotifications ? null : clearAllNotifications,
            icon: clearingNotifications
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.clear_all, size: 18),
            label: const CcsText('Clear all'),
            style: TextButton.styleFrom(foregroundColor: blue),
          ),
          IconButton(
            tooltip: trText('Refresh'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificationCenterItem>>(
        future: itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? const <NotificationCenterItem>[];
          if (!markedRead) {
            markedRead = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }

              notificationCenterUnreadCountsBySource.clear();
              notificationCenterUnreadCount.value = 0;
              unawaited(markNotificationCenterItemsRead(items));
            });
          }

          if (items.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              text: 'Your latest CCS updates will appear here.',
            );
          }

          final displayedItems = items.take(5).toList();
          final hasMore = items.length > 5;

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: displayedItems.length + (hasMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == displayedItems.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          appPageRoute(
                            builder: (_) =>
                                _AllNotificationsScreen(allItems: items),
                          ),
                        );
                      },
                      icon: const Icon(Icons.expand_more),
                      label: CcsText(trText('Show ${items.length - 5} more')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: blue,
                        side: const BorderSide(color: blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final item = displayedItems[index];
              final color = notificationCenterColor(item);

              return InkWell(
                onTap: item.canOpen
                    ? () => openNotificationCenterItem(context, item)
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: item.read
                          ? Colors.white12
                          : color.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(notificationCenterIcon(item), color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CcsText(
                              trText(notificationCenterDisplayTitle(item)),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (notificationCenterDisplayBody(
                              item,
                            ).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              CcsText(
                                trText(notificationCenterDisplayBody(item)),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (notificationCenterTime(
                              item.createdAtMillis,
                            ).isNotEmpty) ...[
                              const SizedBox(height: 7),
                              CcsText(
                                notificationCenterTime(item.createdAtMillis),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (item.canOpen) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white38,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AllNotificationsScreen extends StatefulWidget {
  final List<NotificationCenterItem> allItems;

  const _AllNotificationsScreen({required this.allItems});

  @override
  State<_AllNotificationsScreen> createState() =>
      _AllNotificationsScreenState();
}

class _AllNotificationsScreenState extends State<_AllNotificationsScreen>
    with LanguageReactiveState {
  @override
  Widget build(BuildContext context) {
    final items = widget.allItems;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText('Notifications')),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
      ),
      body: items.isEmpty
          ? const EmptyStateCard(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              text: 'Your latest CCS updates will appear here.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                final color = notificationCenterColor(item);

                return InkWell(
                  onTap: item.canOpen
                      ? () => openNotificationCenterItem(context, item)
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: panelGlass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: item.read
                            ? Colors.white12
                            : color.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            notificationCenterIcon(item),
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CcsText(
                                trText(notificationCenterDisplayTitle(item)),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (notificationCenterDisplayBody(
                                item,
                              ).isNotEmpty) ...[
                                const SizedBox(height: 4),
                                CcsText(
                                  trText(notificationCenterDisplayBody(item)),
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              if (notificationCenterTime(
                                item.createdAtMillis,
                              ).isNotEmpty) ...[
                                const SizedBox(height: 7),
                                CcsText(
                                  notificationCenterTime(item.createdAtMillis),
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (item.canOpen) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.white38,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
