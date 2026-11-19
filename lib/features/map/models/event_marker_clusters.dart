import 'dart:math' as math;
import 'dart:ui';

/// Connected screen-space components; zooming changes projected positions and
/// therefore splits groups. Each input appears exactly once, including chains.
List<List<T>> groupEventMarkers<T>(
  List<T> items,
  Offset Function(T) project, {
  required double width,
  required double height,
}) {
  final points = items.map(project).toList();
  final parents = List.generate(items.length, (i) => i);
  int root(int i) {
    while (parents[i] != i) {
      parents[i] = parents[parents[i]];
      i = parents[i];
    }
    return i;
  }

  final cells = <(int, int), List<int>>{};
  for (var i = 0; i < items.length; i++) {
    final p = points[i];
    final x = (p.dx / width).floor(), y = (p.dy / height).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in cells[(x + dx, y + dy)] ?? <int>[]) {
          if ((p.dx - points[j].dx).abs() < width &&
              (p.dy - points[j].dy).abs() < height) {
            parents[root(i)] = root(j);
          }
        }
      }
    }
    (cells[(x, y)] ??= []).add(i);
  }
  final groups = <int, List<T>>{};
  for (var i = 0; i < items.length; i++) {
    (groups[root(i)] ??= []).add(items[i]);
  }
  return groups.values.toList();
}

class EventMarkerMetrics {
  EventMarkerMetrics(double zoom) {
    dot = zoom < 11.25;
    final city = zoom <= 7
        ? 1.0
        : zoom < 9
        ? 1 - (zoom - 7) * .1
        : zoom <= 12
        ? .8
        : math.min(1.0, .8 + (zoom - 12) * (.2 / 3));
    final p = (dot ? (zoom - 3) / 8.25 : (zoom - 11.25) / 4.75).clamp(0.0, 1.0);
    width =
        (dot
            ? 3.2 + 7.2 * math.pow(p, 2.7)
            : 38 + 27 * (1 - math.pow(1 - p, 3))) *
        city;
    showTime = !dot && zoom >= 14;
    height = dot ? width : width * 36 / 128 + (showTime ? 32 : 0);
  }
  late final bool dot, showTime;
  late final double width, height;
}
