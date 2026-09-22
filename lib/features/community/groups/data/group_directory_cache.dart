import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Directory metadata only: never cache messages or use cached membership to
// authorize a write. The API and Firestore still validate every action.
class GroupDirectoryCache {
  static final Map<String, Map<String, dynamic>> _memory = {};
  static const maxAge = Duration(days: 7);

  static String key(String uid, String country, String access) =>
      'group_directory_v1_${Uri.encodeComponent(uid)}_${country}_${Uri.encodeComponent(access)}';

  static Map<String, dynamic>? peek(String key) => _memory[key];

  static Future<Map<String, dynamic>?> read(String key) async {
    if (_memory.containsKey(key)) return _memory[key];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      final age =
          DateTime.now().millisecondsSinceEpoch -
          (stored['savedAt'] as num).toInt();
      if (age < 0 || age > maxAge.inMilliseconds) return null;
      final data = stored['data'] as Map<String, dynamic>;
      if (data['groups'] is! List || data['visibleGroupIds'] is! List) {
        return null;
      }
      // A network response may already have arrived while storage was loading.
      return _memory.putIfAbsent(key, () => data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> data) async {
    _memory[key] = data;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'data': data,
        }),
      );
    } catch (_) {
      // A full disk must not turn a successful directory refresh into an error.
    }
  }
}
