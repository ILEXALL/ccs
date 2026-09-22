import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../controllers/map_interaction_options.dart';

/// Wrap just the map, so buttons and other screen controls keep their gestures.
class ExclusiveMapGestures extends StatefulWidget {
  const ExclusiveMapGestures({super.key, required this.builder});

  final Widget Function(InteractionOptions options) builder;

  @override
  State<ExclusiveMapGestures> createState() => _ExclusiveMapGesturesState();
}

class _ExclusiveMapGesturesState extends State<ExclusiveMapGestures> {
  final _lock = MapGestureLock();

  @override
  Widget build(BuildContext context) => Listener(
    // Pointer listeners run before gesture-recognizer callbacks. Update the
    // policy synchronously, without waiting a frame for a widget rebuild.
    onPointerDown: _lock.pointerDown,
    onPointerMove: _lock.pointerMove,
    onPointerUp: _lock.pointerEnd,
    onPointerCancel: _lock.pointerEnd,
    child: widget.builder(_lock.options),
  );
}
