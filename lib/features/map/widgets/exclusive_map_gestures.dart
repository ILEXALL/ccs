import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import '../controllers/map_interaction_options.dart';

class ExclusiveMapGestures extends StatefulWidget {
  const ExclusiveMapGestures({
    super.key,
    required this.mapController,
    required this.builder,
  });
  final MapController mapController;
  final Widget Function(InteractionOptions options, CameraConstraint constraint)
  builder;
  @override
  State<ExclusiveMapGestures> createState() => _ExclusiveMapGesturesState();
}

class _ExclusiveMapGesturesState extends State<ExclusiveMapGestures>
    with SingleTickerProviderStateMixin {
  late final _inertia = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(_step);
  late final _lock = MapGestureLock(
    camera: () => widget.mapController.camera,
    // Replace final-segment fling on iOS with sampled velocity, below.
    enableFling: defaultTargetPlatform != TargetPlatform.iOS,
  );
  final _pointers = <int>{};
  VelocityTracker? _velocity;
  Offset _down = Offset.zero;
  Offset _travel = Offset.zero;
  Offset _speed = Offset.zero;
  double _distance = 0;
  int _sequence = 0;
  MapCamera? _previous;
  Duration? _lastMove;

  void _onDown(PointerDownEvent event) {
    _sequence++;
    _inertia.stop();
    _pointers.add(event.pointer);
    _velocity =
        defaultTargetPlatform == TargetPlatform.iOS && _pointers.length == 1
        ? (VelocityTracker.withKind(event.kind)
            ..addPosition(event.timeStamp, event.localPosition))
        : null;
    _down = event.localPosition;
    _travel = Offset.zero;
    _lock.pointerDown(event);
  }

  void _onMove(PointerMoveEvent event) {
    _lock.pointerMove(event);
    if (_velocity == null) return;
    _velocity!.addPosition(event.timeStamp, event.localPosition);
    _lastMove = event.timeStamp;
    _travel = event.localPosition - _down;
  }

  void _onEnd(PointerEvent event) {
    _lock.pointerEnd(event);
    _pointers.remove(event.pointer);
    final tracker = _velocity;
    _velocity = null;
    if (event is! PointerUpEvent ||
        tracker == null ||
        _pointers.isNotEmpty ||
        _travel.distance < kTouchSlop ||
        _lastMove == null ||
        event.timeStamp - _lastMove! > const Duration(milliseconds: 80))
      return;
    // Estimate across recent samples instead of magnifying release jitter.
    var speed = tracker.getVelocity().pixelsPerSecond;
    if (!speed.dx.isFinite || !speed.dy.isFinite || speed.distance < 100)
      return;
    if (speed.dx.abs() < speed.dy.abs() * 0.1) speed = Offset(0, speed.dy);
    if (speed.dy.abs() < speed.dx.abs() * 0.1) speed = Offset(speed.dx, 0);
    if (speed.distance > 4000) speed = speed / speed.distance * 4000;
    final sequence = _sequence;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sequence != _sequence || _pointers.isNotEmpty) return;
      _speed = speed;
      _distance = 0;
      _previous = widget.mapController.camera;
      _inertia.forward(from: 0);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _step() {
    final camera = widget.mapController.camera;
    final previous = _previous;
    // Explicit GPS/spot moves take priority over momentum.
    if (previous != null &&
        (camera.center != previous.center || camera.zoom != previous.zoom)) {
      _inertia.stop();
      return;
    }
    final distance = (1 - math.exp(-5 * _inertia.value)) * 0.18;
    final delta = _speed * (distance - _distance);
    _distance = distance;
    if (delta.distance == 0) return;
    // Use screen space so rotated maps glide in the finger's direction too.
    final moved = widget.mapController.move(
      camera.center,
      camera.zoom,
      offset: delta,
      id: 'ios-swipe-inertia',
    );
    _previous = widget.mapController.camera;
    if (!moved) _inertia.stop();
  }

  @override
  void dispose() {
    _inertia.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onEnd,
    onPointerCancel: _onEnd,
    onPointerPanZoomStart: (event) {
      _sequence++;
      _inertia.stop();
      _velocity = null;
      _lock.panZoomStart(event);
    },
    onPointerPanZoomUpdate: _lock.panZoomUpdate,
    onPointerPanZoomEnd: _lock.pointerEnd,
    child: widget.builder(_lock.options, _lock.constraint),
  );
}
