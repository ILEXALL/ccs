import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ccs_app/core/config/app_config.dart' show telegramAuthBaseUrl;

/// HTTPS server time advanced by monotonic elapsed time, never the device clock.
/// Epoch timestamps are timezone-independent: changing a country/timezone cannot
/// make a scheduled event become visible early. Unknown/stale time fails closed.
class TrustedClock extends ChangeNotifier {
  final Stopwatch _elapsed = Stopwatch();
  int? _serverMillis;
  bool _syncing = false;
  Timer? _timer;
  int? get nowMillis =>
      _serverMillis == null || _elapsed.elapsed > const Duration(minutes: 15)
      ? null
      : _serverMillis! + _elapsed.elapsedMilliseconds;
  @visibleForTesting
  void setSampleForTesting(int? millis) {
    _serverMillis = millis;
    _elapsed
      ..reset()
      ..start();
  }

  void start() {
    unawaited(sync());
    _timer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(sync()),
    );
  }

  Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.headUrl(
        Uri.parse(
          '$telegramAuthBaseUrl/api/community?clock=${Stopwatch().hashCode}',
        ),
      );
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final date = response.headers.value(HttpHeaders.dateHeader);
      if (date == null) return;
      // Date is second-granularity. No RTT compensation: reveal may be slightly
      // late but must never become early due to estimated network latency.
      _serverMillis = HttpDate.parse(date).millisecondsSinceEpoch;
      _elapsed
        ..reset()
        ..start();
      notifyListeners();
    } catch (_) {
      /* Keep a recent trusted sample; otherwise remain locked. */
    } finally {
      client.close(force: true);
      _syncing = false;
    }
  }
}

final trustedClock = TrustedClock();
