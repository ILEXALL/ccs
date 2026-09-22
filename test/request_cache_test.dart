import 'dart:async';
import 'package:ccs_app/core/cache/request_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shares reads, expires and separates accounts', () async {
    var now = DateTime(2026);
    final cache = RequestCache<int>(
      ttl: const Duration(seconds: 60),
      now: () => now,
    );
    var calls = 0;
    final pending = Completer<int>();
    final first = cache.get('user-a', () {
      calls++;
      return pending.future;
    });
    final second = cache.get('user-a', () async => ++calls);
    pending.complete(48);
    expect(await first, 48);
    expect(await second, 48);
    expect(await cache.get('user-a', () async => ++calls), 48);
    expect(calls, 1);
    expect(await cache.get('user-b', () async => ++calls), 2);
    now = now.add(const Duration(seconds: 61));
    expect(await cache.get('user-a', () async => ++calls), 3);
  });
  test(
    'failed reads retry and invalidation prevents stale in-flight caching',
    () async {
      final cache = RequestCache<int>(ttl: const Duration(minutes: 1));
      await expectLater(
        cache.get('a', () async => throw StateError('offline')),
        throwsStateError,
      );
      expect(await cache.get('a', () async => 1), 1);
      cache.clear();
      final pending = Completer<int>();
      final old = cache.get('a', () => pending.future);
      cache.clear();
      expect(await cache.get('a', () async => 2), 2);
      pending.complete(1);
      await old;
      expect(await cache.get('a', () async => 3), 2);
    },
  );
}
