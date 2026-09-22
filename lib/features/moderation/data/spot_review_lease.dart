import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show spotsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/features/moderation/data/moderation_api.dart'
    show sendModerationAction;

class SpotReviewLease extends ChangeNotifier {
  final String spotId;
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String sessionId = spotsCollection().doc().id;
  final Stopwatch _confirmedAge = Stopwatch();
  Timer? _heartbeat;
  Future<void>? _renewing;
  bool _held = false;
  bool _closed = false;
  bool _foreground = true;
  bool busy = false;
  String reviewerUsername = '';
  String errorText = '';

  SpotReviewLease(this.spotId);
  bool get active =>
      !_closed &&
      _foreground &&
      _held &&
      _confirmedAge.isRunning &&
      _confirmedAge.elapsed < const Duration(seconds: 75);

  Future<Map<String, dynamic>> _send(String operation) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid || uid.isEmpty) {
      throw StateError('Review account changed');
    }
    return sendModerationAction({
      'action': 'spot_review',
      'operation': operation,
      'spotId': spotId,
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
      throw StateError('Unsupported spot review response');
    }
    if (result['acquired'] == false) {
      _held = false;
      reviewerUsername = stringFromFirebase(result['reviewerUsername'], '');
      notifyListeners();
      return false;
    }
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
      if (result['ok'] == false || result['renewed'] != true) {
        throw StateError('Unsupported spot review response');
      }
      if (_closed || !_foreground) throw StateError('Review is not active');
      _confirm();
      notifyListeners();
    } catch (error, stack) {
      markLost(error: error);
      debugPrint('Spot review renewal failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> ensureActive() async {
    if (!active) {
      throw StateError(trText('Review session ended. Reopen the review page.'));
    }
    await renew();
  }

  void markLost({Object? error, bool opening = false}) {
    _held = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    reviewerUsername = '';
    final details = error?.toString().toLowerCase() ?? '';
    if (error is TimeoutException || error is SocketException) {
      errorText = 'Could not connect to the review server. Please try again.';
    } else if (details.contains('unknown action') ||
        details.contains('unsupported spot review response') ||
        details.contains('request failed 404')) {
      errorText = 'The review server needs updating. Contact an admin.';
    } else if (details.contains('no permission') ||
        details.contains('permission-denied')) {
      errorText = 'No permission to review this spot.';
    } else {
      errorText = opening
          ? 'Could not open spot review. Please try again.'
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
    _heartbeat?.cancel();
    unawaited(release());
    super.dispose();
  }
}
