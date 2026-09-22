import 'package:flutter/material.dart';

import '../localization/app_language.dart';

/// Shared by routes, sheets and dialogs via MaterialApp.builder.
class AppKeyboardDismissal extends StatelessWidget {
  const AppKeyboardDismissal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Actions(
      actions: {
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (ios && keyboard > 0)
              Positioned(
                right: 12,
                bottom: keyboard + 8,
                child: Material(
                  color: const Color(0xFF20242C),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(10),
                  child: TextButton.icon(
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    icon: const Icon(Icons.keyboard_hide_outlined, size: 20),
                    label: Text(switch (appUiPreferences.language) {
                      AppLanguage.en => 'Done',
                      AppLanguage.ru => 'Готово',
                      AppLanguage.lv => 'Gatavs',
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
