import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

RegExpMatch? activeMention(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.end > value.text.length) {
    return null;
  }
  return RegExp(
    r'(?<![A-Za-z0-9_@])@([A-Za-z0-9_]{2,30})$',
  ).firstMatch(value.text.substring(0, selection.end));
}
