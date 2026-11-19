import 'package:flutter/material.dart';

/// Only long press competes in the gesture arena: child link/photo/reaction
/// taps still work, and scrolling cancels the hold before actions can open.
class MessageBubbleActions extends StatelessWidget {
  const MessageBubbleActions({
    super.key,
    required this.child,
    this.onLongPress,
  });
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    onLongPress: onLongPress,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      excludeFromSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: child,
      ),
    ),
  );
}
