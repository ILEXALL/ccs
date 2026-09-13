import 'dart:async';

/// One upstream listener shared by badges, with the last count replayed to new
/// widgets. Disposal prevents an old account's callbacks reaching the new UI.
class SessionCountStream {
  SessionCountStream(this.source);
  final Stream<int> Function() source;
  final _listeners = <MultiStreamController<int>>{};
  StreamSubscription<int>? _subscription;
  int _last = 0;
  int _generation = 0;
  bool _disposed = false;

  late final Stream<int> stream = Stream<int>.multi((listener) {
    if (_disposed) {
      listener.close();
      return;
    }
    _listeners.add(listener);
    listener.add(_last);
    if (_subscription == null) {
      final generation = ++_generation;
      _subscription = source().listen(
        (count) {
          if (_disposed || generation != _generation) return;
          _last = count;
          for (final sink in _listeners.toList()) {
            sink.add(count);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed || generation != _generation) return;
          for (final sink in _listeners.toList()) {
            sink.addError(error, stack);
          }
        },
      );
    }
    listener.onCancel = () async {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        _generation++;
        final subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
      }
    };
  }, isBroadcast: true);

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    for (final sink in _listeners.toList()) {
      sink.close();
    }
    _listeners.clear();
    await subscription?.cancel();
  }
}
