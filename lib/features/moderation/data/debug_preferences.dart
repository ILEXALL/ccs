import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

final firestoreDebugButtonVisible = ValueNotifier<bool>(true);

const firestoreDebugButtonVisibleKey = 'firestore_debug_button_visible';

Future<void> loadFirestoreDebugButtonPreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    firestoreDebugButtonVisible.value =
        prefs.getBool(firestoreDebugButtonVisibleKey) ?? true;
  } catch (_) {}
}

Future<void> saveFirestoreDebugButtonPreference(bool value) async {
  if (currentUser.role != UserRole.admin) return;
  firestoreDebugButtonVisible.value = value;

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(firestoreDebugButtonVisibleKey, value);
  } catch (_) {}
}
