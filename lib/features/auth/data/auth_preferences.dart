import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show rememberMeEnabled, rememberMeKey;

Future<bool> loadRememberMePreference() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(rememberMeKey) ?? true;
}

Future<void> saveRememberMePreference(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(rememberMeKey, value);
  rememberMeEnabled = value;
}
