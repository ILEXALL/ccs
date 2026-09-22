import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';

enum _MapGesture { undecided, zoom, rotate }

/// One decision per touch sequence, released when all fingers leave the map.
class MapGestureLock {
  final _pointers = <int, Offset>{};
  Offset? _initialVector;
  _MapGesture _gesture = _MapGesture.undecided;

  late final InteractionOptions options = _LockedInteractionOptions(this);

  int get flags {
    // Leave normal dragging, taps and wheel zoom to flutter_map. Its two-finger
    // scale handler reads these flags on every update, before changing camera.
    const base =
        InteractiveFlag.all &
        ~(InteractiveFlag.pinchZoom | InteractiveFlag.rotate);
    return switch (_gesture) {
      _MapGesture.undecided => base,
      _MapGesture.zoom => base | InteractiveFlag.pinchZoom,
      _MapGesture.rotate =>
        (base & ~InteractiveFlag.pinchMove) | InteractiveFlag.rotate,
    };
  }

  void pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _initialVector ??= _vector;
  }

  void pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_gesture != _MapGesture.undecided) return;
    final vector = _vector;
    final initial = _initialVector;
    if (vector == null || initial == null) return;
    if (initial.distance < 1) {
      _initialVector = vector;
      return;
    }
    if (vector.distance < 1) return;

    final zoomDelta = math.log(vector.distance / initial.distance) / math.ln2;
    final angle = math
        .atan2(
          initial.dx * vector.dy - initial.dy * vector.dx,
          initial.dx * vector.dx + initial.dy * vector.dy,
        )
        .abs();

    // Ignore small finger jitter. Zoom takes precedence if both thresholds are
    // crossed in the same event, matching the map package's usual preference.
    if (zoomDelta.abs() >= 0.08) {
      _gesture = _MapGesture.zoom;
    } else if (angle >= 8 * math.pi / 180) {
      _gesture = _MapGesture.rotate;
    }
  }

  void pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) {
      _gesture = _MapGesture.undecided;
      _initialVector = null;
    } else if (_pointers.length < 2) {
      _initialVector = null;
    }
  }

  Offset? get _vector {
    if (_pointers.length < 2) return null;
    final pair = _pointers.values.take(2).toList();
    return pair[1] - pair[0];
  }
}

class _LockedInteractionOptions extends InteractionOptions {
  const _LockedInteractionOptions(this.lock)
    // Keep the package's additive scale correction disabled: fast pinch
    // reversals can otherwise produce invalid scales or sudden zoom jumps.
    : super(enableMultiFingerGestureRace: false);

  final MapGestureLock lock;

  @override
  int get flags => lock.flags;

  // This options object is a stable, live gesture policy, not a value snapshot.
  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);
}
