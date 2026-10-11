import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:ccs_app/core/config/app_config.dart' show spotVisitUrl;
import 'package:ccs_app/core/network/json_http.dart' show postJsonToUrl;

/// Private, server-confirmed status. Device clock changes cannot prolong a day.
class DailyVisitStatus extends ChangeNotifier {
  String? _uid;
  Set<String> _spots = {};
  final Stopwatch _age = Stopwatch();
  int _validForMs = 0;
  Timer? _timer;
  Timer? _expiryTimer;
  bool _refreshAgain = false;
  StreamSubscription<User?>? _auth;
  int _users = 0;
  bool _loading = false;
  bool contains(String id) =>
      Firebase.apps.isNotEmpty &&
      _uid == FirebaseAuth.instance.currentUser?.uid &&
      _age.isRunning &&
      _age.elapsedMilliseconds < _validForMs &&
      _spots.contains(id);

  void attach() {
    if (++_users != 1 || Firebase.apps.isEmpty) return;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_uid != user?.uid) {
        _uid = user?.uid;
        _spots = {};
        _validForMs = 0;
        notifyListeners();
      }
      unawaited(refresh(force: true));
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_age.isRunning &&
          _age.elapsedMilliseconds >= _validForMs &&
          _spots.isNotEmpty) {
        _spots = {};
        notifyListeners();
      }
      if (!_age.isRunning ||
          _age.elapsedMilliseconds >= 300000 ||
          _age.elapsedMilliseconds >= _validForMs) {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
  }

  void detach() {
    if (--_users > 0) return;
    _users = 0;
    _timer?.cancel();
    _expiryTimer?.cancel();
    unawaited(_auth?.cancel());
    _auth = null;
  }

  Future<void> refresh({bool force = false}) async {
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_loading) {
      _refreshAgain = _refreshAgain || force;
      return;
    }
    _loading = true;
    final requestAge = Stopwatch()..start();
    try {
      final token = await user.getIdToken();
      final response = await postJsonToUrl(
        spotVisitUrl,
        {'action': 'status'},
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      if (response['ok'] != true ||
          FirebaseAuth.instance.currentUser?.uid != user.uid) {
        return;
      }
      final result = response['result'] as Map;
      _uid = user.uid;
      _spots = (result['spotIds'] as List).whereType<String>().toSet();
      _validForMs =
          ((result['expiresAt'] as num).toInt() -
                  (result['serverNow'] as num).toInt() -
                  requestAge.elapsedMilliseconds)
              .clamp(0, 100000000);
      _age
        ..reset()
        ..start();
      _expiryTimer?.cancel();
      if (_users > 0) {
        _expiryTimer = Timer(Duration(milliseconds: _validForMs), () {
          _spots = {};
          notifyListeners();
          unawaited(refresh(force: true));
        });
      }
      notifyListeners();
    } catch (_) {
      // Retain confirmed status only until its original server day expires.
    } finally {
      _loading = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }
}

final dailyVisitStatus = DailyVisitStatus();
