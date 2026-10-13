import 'dart:async';
import 'package:flutter/material.dart';

OverlayEntry? _submissionNotice;
Timer? _submissionNoticeTimer;

/// Independent of ScaffoldMessenger's route/animation queue, including when
/// the creation tab remains mounted behind the map in an IndexedStack.
void showTransientSnackBar(BuildContext context, SnackBar message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.clearSnackBars();
  messenger?.removeCurrentSnackBar();
  _submissionNoticeTimer?.cancel();
  _submissionNotice?.remove();
  _submissionNotice?.dispose();
  late final OverlayEntry entry;
  void dismiss() {
    if (!identical(_submissionNotice, entry)) return;
    _submissionNoticeTimer?.cancel();
    _submissionNotice = null;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).padding.bottom + 80,
      child: Material(
        color: message.backgroundColor ?? const Color(0xFF0066FF),
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  child: message.content,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: dismiss,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  entry.addListener(() {
    if (!entry.mounted && identical(_submissionNotice, entry)) {
      _submissionNoticeTimer?.cancel();
      _submissionNotice = null;
    }
  });
  _submissionNotice = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
  _submissionNoticeTimer = Timer(message.duration, dismiss);
}
