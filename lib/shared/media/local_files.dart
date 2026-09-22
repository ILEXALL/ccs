import 'dart:io';

bool localFileExists(String? path) {
  if (path == null || path.trim().isEmpty) {
    return false;
  }

  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}
