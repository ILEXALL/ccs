import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/query_pages.dart';

void main() {
  for (final count in [0, 119, 120, 121, 360, 367]) {
    test('cursor paging returns every record across $count topics', () async {
      final source = List.generate(count, (i) => i);
      final cursors = <int?>[];
      final result = await collectQueryPages<int>(
        pageSize: 120,
        readPage: (cursor, size) async {
          cursors.add(cursor);
          return source
              .skip(cursor == null ? 0 : cursor + 1)
              .take(size)
              .toList();
        },
      );
      expect(result, source);
      expect(cursors.length, count ~/ 120 + 1);
      if (count >= 120) expect(cursors[1], 119);
    });
  }
  test(
    'a failed later page does not return a misleading partial success',
    () async {
      await expectLater(
        collectQueryPages<int>(
          pageSize: 2,
          readPage: (cursor, _) async {
            if (cursor != null) throw StateError('offline');
            return [1, 2];
          },
        ),
        throwsStateError,
      );
    },
  );
}
