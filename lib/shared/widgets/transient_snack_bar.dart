import 'dart:async';
import 'package:flutter/material.dart';

/// Submission feedback must not survive an interrupted snackbar animation or
/// a route covering the messenger. The fallback is independent of frame ticks.
void showTransientSnackBar(BuildContext context, SnackBar message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.removeCurrentSnackBar();
  final controller = messenger.showSnackBar(message);
  var closed = false;
  final fallback = Timer(message.duration + const Duration(seconds: 1), () {
    if (!closed && messenger.mounted) messenger.removeCurrentSnackBar();
  });
  unawaited(
    controller.closed.then((_) {
      closed = true;
      fallback.cancel();
    }),
  );
}
