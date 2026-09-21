/// Shares concurrent loads, without caching completed results or errors.
class InFlightLoad<K, V> {
  final Map<K, Future<V>> _pending = {};

  Future<V> run(K key, Future<V> Function() load) {
    final pending = _pending[key];
    if (pending != null) return pending;
    late final Future<V> request;
    request = Future<V>.sync(load).whenComplete(() {
      if (identical(_pending[key], request)) _pending.remove(key);
    });
    _pending[key] = request;
    return request;
  }
}
