import 'dart:async';
import 'package:ccs_app/session_count_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shares one backend listener and replays the count to a new badge',
    () async {
      var starts = 0;
      var cancels = 0;
      final source = StreamController<int>.broadcast(
        onListen: () => starts++,
        onCancel: () => cancels++,
      );
      final session = SessionCountStream(() => source.stream);
      final first = <int>[];
      final a = session.stream.listen(first.add);
      source.add(5);
      await Future<void>.delayed(Duration.zero);
      final second = <int>[];
      final b = session.stream.listen(second.add);
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      expect(first.last, 5);
      expect(second, [5]);
      await a.cancel();
      expect(cancels, 0);
      await b.cancel();
      expect(cancels, 1);
      await session.dispose();
      await source.close();
    },
  );
  test('sign-out closes badges and discards further account events', () async {
    final source = StreamController<int>.broadcast();
    final session = SessionCountStream(() => source.stream);
    final values = <int>[];
    var done = false;
    session.stream.listen(values.add, onDone: () => done = true);
    await Future<void>.delayed(Duration.zero);
    await session.dispose();
    source.add(9);
    await Future<void>.delayed(Duration.zero);
    expect(done, true);
    expect(values, [0]);
    expect(await session.stream.toList(), isEmpty);
    await source.close();
  });
}
