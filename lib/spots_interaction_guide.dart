import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show Drag;
import 'package:shared_preferences/shared_preferences.dart';

/// A gesture-driven introduction, persisted per installation, not per account.
class SpotsInteractionGuide extends StatefulWidget {
  const SpotsInteractionGuide({
    super.key,
    required this.categorySlider,
    required this.cards,
    required this.hasCards,
    required this.isVisible,
    required this.translate,
    required this.categoryController,
    required this.cardsController,
  });

  static const progressKey = 'spots_interaction_guide_progress_v1';
  final Widget categorySlider;
  final Widget cards;
  final bool hasCards;
  final bool isVisible;
  final String Function(String) translate;
  final ScrollController categoryController;
  final ScrollController cardsController;

  @override
  State<SpotsInteractionGuide> createState() => _SpotsInteractionGuideState();
}

class _SpotsInteractionGuideState extends State<SpotsInteractionGuide>
    with WidgetsBindingObserver {
  final _categoryKey = GlobalKey();
  final _cardsKey = GlobalKey();
  final _promptKey = GlobalKey();
  OverlayEntry? _overlay;
  Rect _targetRect = Rect.zero;
  Rect _promptRect = Rect.zero;
  Drag? _drag;
  SharedPreferences? _preferences;
  int? _step;
  double _dragDistance = 0;
  bool _dragging = false;
  Future<void> _save = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drag?.cancel();
    _overlay?.remove();
    _overlay?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _scheduleOverlay();

  void _scheduleOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isActive(0) && !_isActive(1)) {
        _drag?.cancel();
        _drag = null;
        _overlay?.remove();
        _overlay?.dispose();
        _overlay = null;
        return;
      }
      final overlay = Overlay.of(context, rootOverlay: true);
      final overlayBox = overlay.context.findRenderObject() as RenderBox;
      Rect bounds(GlobalKey key) {
        final box = key.currentContext!.findRenderObject() as RenderBox;
        return box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
      }

      _targetRect = bounds(_step == 0 ? _categoryKey : _cardsKey);
      _promptRect = bounds(_promptKey);
      if (_overlay == null) {
        FocusManager.instance.primaryFocus?.unfocus();
        _overlay = OverlayEntry(builder: _buildOverlay);
        overlay.insert(_overlay!);
      } else {
        _overlay!.markNeedsBuild();
      }
    });
  }

  void _startDrag(DragStartDetails details) {
    final controller = _step == 0
        ? widget.categoryController
        : widget.cardsController;
    if (!controller.hasClients) return;
    _drag = controller.position.drag(details, () => _drag = null);
  }

  void _endDrag(DragEndDetails details) {
    final drag = _drag;
    _drag = null;
    // A completed finger gesture counts immediately, even while the list
    // continues coasting or the category slider snaps into place.
    _finishGesture();
    drag?.end(details);
  }

  void _cancelDrag() {
    _dragging = false;
    _dragDistance = 0;
    _drag?.cancel();
    _drag = null;
  }

  void _finishGesture() {
    final step = _step;
    final completed = _dragging && _dragDistance.abs() >= 40;
    _dragging = false;
    _dragDistance = 0;
    if (!completed || step == null || !_isActive(step)) return;
    setState(() => _step = step + 1);
    // Serialize writes so a fast second gesture cannot save an older step last.
    _save = _save.then((_) async {
      try {
        await _preferences!.setInt(SpotsInteractionGuide.progressKey, step + 1);
      } catch (error) {
        debugPrint('Could not save Spots guide progress: $error');
      }
    });
  }

  Widget _buildOverlay(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: ModalBarrier(
          key: ValueKey('spots-guide-barrier'),
          dismissible: false,
          color: Colors.transparent,
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _GuideDimmer(_targetRect, _promptRect)),
        ),
      ),
      Positioned.fromRect(
        rect: _targetRect,
        child: Listener(
          onPointerCancel: (_) => _cancelDrag(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _step == 0 ? _startDrag : null,
            onHorizontalDragUpdate: _step == 0
                ? (details) => _drag?.update(details)
                : null,
            onHorizontalDragEnd: _step == 0 ? _endDrag : null,
            onHorizontalDragCancel: _step == 0 ? _cancelDrag : null,
            onVerticalDragStart: _step == 1 ? _startDrag : null,
            onVerticalDragUpdate: _step == 1
                ? (details) => _drag?.update(details)
                : null,
            onVerticalDragEnd: _step == 1 ? _endDrag : null,
            onVerticalDragCancel: _step == 1 ? _cancelDrag : null,
            child: Semantics(
              label: widget.translate(
                _step == 0
                    ? 'Swipe the categories left or right to explore.'
                    : 'Swipe the spot cards up or down to browse.',
              ),
              liveRegion: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _step = (preferences.getInt(SpotsInteractionGuide.progressKey) ?? 0)
            .clamp(0, 2);
      });
    } catch (error) {
      debugPrint('Could not load Spots guide progress: $error');
    }
  }

  @override
  void didUpdateWidget(covariant SpotsInteractionGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVisible || oldWidget.hasCards != widget.hasCards) {
      _dragging = false;
      _dragDistance = 0;
    }
  }

  bool _isActive(int step) =>
      widget.isVisible && _step == step && (step == 0 || widget.hasCards);

  bool _observe(ScrollNotification notification, int step) {
    if (!_isActive(step) ||
        notification.depth != 0 ||
        notification.metrics.axis !=
            (step == 0 ? Axis.horizontal : Axis.vertical)) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      // Preserve the finger gesture if the child's end listener starts snapping.
      if (notification.dragDetails != null) {
        _dragging = true;
        _dragDistance = 0;
      }
    } else if (_dragging &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _dragDistance += notification.dragDetails!.primaryDelta ?? 0;
    } else if (_dragging &&
        notification is OverscrollNotification &&
        notification.dragDetails != null) {
      // Short lists still teach the gesture through their edge resistance.
      _dragDistance += notification.dragDetails!.primaryDelta ?? 0;
    } else if (notification is ScrollEndNotification) {
      _finishGesture();
    }
    return false;
  }

  Widget _target(Widget child, int step) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) => _observe(notification, step),
        child: DecoratedBox(
          key: step == 0 ? _categoryKey : _cardsKey,
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: _isActive(step)
                ? Border.all(color: Colors.cyanAccent, width: 2)
                : null,
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final showPrompt = _isActive(0) || _isActive(1);
    _scheduleOverlay();
    return PopScope(
      canPop: !showPrompt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPrompt)
            Semantics(
              liveRegion: true,
              child: Container(
                key: _promptKey,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12313C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _step == 0 ? Icons.swipe : Icons.swipe_vertical,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.translate(
                          _step == 0
                              ? '1/2 · Swipe the categories left or right to explore.'
                              : '2/2 · Swipe the spot cards up or down to browse.',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _target(widget.categorySlider, 0),
          const SizedBox(height: 10),
          Expanded(child: _target(widget.cards, 1)),
        ],
      ),
    );
  }
}

class _GuideDimmer extends CustomPainter {
  const _GuideDimmer(this.target, this.prompt);

  final Rect target;
  final Rect prompt;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(target, const Radius.circular(12)))
      ..addRRect(RRect.fromRectAndRadius(prompt, const Radius.circular(12)));
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
  }

  @override
  bool shouldRepaint(_GuideDimmer oldDelegate) =>
      target != oldDelegate.target || prompt != oldDelegate.prompt;
}
