/// Shares concurrent reads and briefly reuses successful results. Errors retry.
class RequestCache<T> {
  RequestCache({required this.ttl, DateTime Function()? now})
    : now = now ?? DateTime.now;
  final Duration ttl;
  final DateTime Function() now;
  final _values = <String, (DateTime, T)>{};
  final _pending = <String, Future<T>>{};
  int _generation = 0;

  Future<T> get(String key, Future<T> Function() load) {
    _values.removeWhere((_, value) => now().difference(value.$1) >= ttl);
    final value = _values[key];
    if (value != null && now().difference(value.$1) < ttl)
      return Future.value(value.$2);
    if (_pending[key] case final request?) return request;
    final generation = _generation;
    late final Future<T> request;
    request = Future.sync(load)
        .then((value) {
          if (generation == _generation) {
            if (_values.length >= 128) _values.remove(_values.keys.first);
            _values[key] = (now(), value);
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_pending[key], request)) _pending.remove(key);
        });
    _pending[key] = request;
    return request;
  }

  void clear() {
    _generation++;
    _values.clear();
    _pending.clear();
  }
}
