DateTime notificationLaunchTime = DateTime.now();

class NotificationFreshness {
  final DateTime startedAt;
  final Set<String> _seen = {};
  NotificationFreshness(this.startedAt);
  void seed(Iterable<String> ids) => _seen.addAll(ids);
  bool accept(String id, DateTime? createdAt) {
    if (!_seen.add(id)) return false;
    return createdAt != null && createdAt.isAfter(startedAt);
  }
}
