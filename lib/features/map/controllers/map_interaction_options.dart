import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';

enum _MapGesture { undecided, zoom, rotate }

/// One decision per touch sequence, released when all fingers leave the map.
class MapGestureLock {
  MapGestureLock({this.camera, this.enableFling = true});

  final bool enableFling;

  final MapCamera Function()? camera;
  final _pointers = <int, Offset>{};
  final _panZoomPointers = <int>{};
  Offset? _initialVector;
  MapCamera? _startCamera;
  _MapGesture _gesture = _MapGesture.undecided;

  late final InteractionOptions options = _LockedInteractionOptions(this);
  late final CameraConstraint constraint = _LockedCameraConstraint(this);

  int get flags {
    // Leave normal dragging, taps and wheel zoom to flutter_map. Its two-finger
    // scale handler reads these flags on every update, before changing camera.
    final base =
        InteractiveFlag.all &
        ~(InteractiveFlag.pinchZoom |
            InteractiveFlag.rotate |
            (enableFling ? 0 : InteractiveFlag.flingAnimation));
    return switch (_gesture) {
      _MapGesture.undecided => base,
      _MapGesture.zoom => base | InteractiveFlag.pinchZoom,
      _MapGesture.rotate =>
        (base & ~InteractiveFlag.pinchMove) | InteractiveFlag.rotate,
    };
  }

  void pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) _startCamera ??= camera?.call();
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

    _chooseGesture(zoomDelta, angle);
  }

  void _chooseGesture(double zoomDelta, double angle) {
    if (_gesture != _MapGesture.undecided) return;
    if (!zoomDelta.isFinite || !angle.isFinite) return;
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
    _panZoomPointers.remove(event.pointer);
    if (_pointers.isEmpty && _panZoomPointers.isEmpty) {
      _gesture = _MapGesture.undecided;
      _initialVector = null;
      _startCamera = null;
    } else if (_pointers.length < 2) {
      _initialVector = null;
    }
  }

  void panZoomStart(PointerPanZoomStartEvent event) {
    _panZoomPointers.add(event.pointer);
    _startCamera ??= camera?.call();
  }

  void panZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_panZoomPointers.contains(event.pointer) || event.scale <= 0) return;
    _chooseGesture(math.log(event.scale) / math.ln2, event.rotation.abs());
  }

  MapCamera constrain(MapCamera next) {
    final start = _startCamera;
    if (start == null) return next;
    // Enforce the decision at the camera as well as at the recognizer. This
    // prevents combined platform gesture updates and camera-follow updates
    // from changing the locked axis, regardless of event delivery order.
    if (_gesture != _MapGesture.zoom) {
      next = next.withPosition(zoom: start.zoom);
    }
    if (_gesture != _MapGesture.rotate) {
      next = next.withRotation(start.rotation);
    }
    return next;
  }

  Offset? get _vector {
    if (_pointers.length < 2) return null;
    final pair = _pointers.values.take(2).toList();
    return pair[1] - pair[0];
  }
}

class _LockedCameraConstraint extends CameraConstraint {
  const _LockedCameraConstraint(this.lock);
  final MapGestureLock lock;

  @override
  MapCamera constrain(MapCamera camera) => lock.constrain(camera);
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
