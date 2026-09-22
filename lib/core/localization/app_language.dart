import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { en, ru, lv }

class AppUiPreferences extends ChangeNotifier {
  static const languageKey = 'app_language';
  static const lightThemeKey = 'app_light_theme';

  AppLanguage language = AppLanguage.en;
  bool lightTheme = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      language = AppLanguage.values.firstWhere(
        (value) => value.name == prefs.getString(languageKey),
        orElse: () => AppLanguage.en,
      );
      // Light theme is disabled: CCS uses the dark map/glass design only.
      lightTheme = false;
      await prefs.setBool(lightThemeKey, false);
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) {
      return;
    }

    language = value;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(languageKey, value.name);
    } catch (_) {}
  }

  Future<void> setLightTheme(bool value) async {
    // Light theme is removed from the app. Keep this method only so old calls do not break.
    if (!lightTheme) {
      return;
    }

    lightTheme = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(lightThemeKey, false);
    } catch (_) {}
  }
}

final appUiPreferences = AppUiPreferences();
