import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;

class ForumReviewLease extends ChangeNotifier {
  final String uid;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  requestAction;
  List<Map<String, dynamic>> topics = [];
  final String sessionId =
      '${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(1 << 32)}';
  final Stopwatch _confirmedAge = Stopwatch();
  Timer? _heartbeat;
  Future<void>? _renewing;
  bool _held = false;
  bool _closed = false;
  bool _foreground = true;
  bool busy = false;
  String reviewerUsername = '';
  String errorText = '';

  ForumReviewLease({this.requestAction, String? userId})
    : uid = userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  void checkBlocked(Map<String, dynamic> result) {
    if (result['blocked'] != true) return;
    markLost();
    reviewerUsername = stringFromFirebase(
      result['reviewerUsername'],
      'another reviewer',
    );
    errorText = '';
    if (!_closed) notifyListeners();
    throw StateError(
      'Forum review is currently being checked by @$reviewerUsername',
    );
  }

  void readTopics(Map<String, dynamic> result) {
    topics = (result['topics'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
  }

  bool get active =>
      (requestAction != null ||
          FirebaseAuth.instance.currentUser?.uid == uid) &&
      !_closed &&
      _foreground &&
      _held &&
      _confirmedAge.isRunning &&
      _confirmedAge.elapsed < const Duration(seconds: 75);

  Future<Map<String, dynamic>> _send(String operation) async {
    if ((requestAction == null &&
            FirebaseAuth.instance.currentUser?.uid != uid) ||
        uid.isEmpty) {
      throw StateError('Review account changed');
    }
    return (requestAction ?? sendModerationAction)({
      'action': 'forum_review',
      'operation': operation,
      'sessionId': sessionId,
    }).timeout(const Duration(seconds: 15));
  }

  void _confirm() {
    _held = true;
    errorText = '';
    _confirmedAge
      ..reset()
      ..start();
    _heartbeat ??= Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_closed || !_foreground || !_held) return;
      try {
        await renew();
      } catch (_) {
        /* renew marks the session lost */
      }
    });
  }

  Future<bool> acquire() async {
    errorText = '';
    reviewerUsername = '';
    final result = await _send('acquire');
    if (_closed || !_foreground) {
      unawaited(release());
      return false;
    }
    if (result['ok'] == false || result['acquired'] is! bool) {
      throw StateError('Unsupported forum review response');
    }
    if (result['acquired'] == false) {
      _held = false;
      reviewerUsername = stringFromFirebase(result['reviewerUsername'], '');
      notifyListeners();
      return false;
    }
    readTopics(result);
    _confirm();
    notifyListeners();
    return true;
  }

  Future<void> renew() async {
    if (_closed || !_foreground) throw StateError('Review is not active');
    final existing = _renewing;
    if (existing != null) return existing;
    final future = _renew();
    _renewing = future;
    try {
      await future;
    } finally {
      if (identical(_renewing, future)) _renewing = null;
    }
  }

  Future<void> _renew() async {
    try {
      final result = await _send('renew');
      if (result['blocked'] == true) {
        try {
          checkBlocked(result);
        } catch (_) {}
        return;
      }
      if (result['ok'] == false || result['renewed'] != true) {
        throw StateError('Unsupported forum review response');
      }
      if (_closed || !_foreground) throw StateError('Review is not active');
      readTopics(result);
      _confirm();
      notifyListeners();
    } catch (error, stack) {
      markLost(error: error);
      debugPrint('Forum review renewal failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> ensureActive() async {
    if (!active) {
      throw StateError(trText('Review session ended. Reopen the review page.'));
    }
    await renew();
    if (!active) throw StateError('Review session is no longer active');
  }

  void markLost({Object? error, bool opening = false}) {
    _held = false;
    topics = [];
    _heartbeat?.cancel();
    _heartbeat = null;
    reviewerUsername = '';
    final details = error?.toString().toLowerCase() ?? '';
    if (error is TimeoutException || error is SocketException) {
      errorText = 'Could not connect to the review server. Please try again.';
    } else if (details.contains('unknown action') ||
        details.contains('unsupported forum review response') ||
        details.contains('request failed 404')) {
      errorText = 'The review server needs updating. Contact an admin.';
    } else if (details.contains('no permission') ||
        details.contains('permission-denied')) {
      errorText = 'No permission to review forum topics.';
    } else {
      errorText = opening
          ? 'Could not open forum review. Please try again.'
          : 'Review session ended. Reopen the review page.';
    }
    if (!_closed) notifyListeners();
  }

  void suspend() {
    _foreground = false;
    markLost();
  }

  Future<void> resume() async {
    _foreground = true;
    try {
      await renew();
    } catch (_) {}
  }

  Future<void> runAction(Future<void> Function() action) async {
    if (busy || !active) return;
    busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> release() async {
    try {
      await _send('release');
    } catch (_) {
      // A failed release recovers through the server's 90-second expiry.
    }
  }

  @override
  void dispose() {
    _closed = true;
    _held = false;
    topics = [];
    _heartbeat?.cancel();
    unawaited(release());
    super.dispose();
  }
}
