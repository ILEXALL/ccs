import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/firestore_usage_estimate.dart';

void main() {
  test(
    'cached initial documents are excluded; server result counted only once',
    () {
      final counter = ServerReadEstimate();
      final data = {
        'a': {
          'x': [1, 2],
        },
        'b': 2,
      };
      expect(counter.observe(data, fromCache: true, pendingWrites: false), 0);
      expect(counter.observe(data, fromCache: false, pendingWrites: false), 2);
      expect(
        counter.observe(
          {
            'a': {
              'x': [1, 2],
            },
            'b': 2,
          },
          fromCache: false,
          pendingWrites: false,
        ),
        0,
      );
      expect(
        counter.observe(
          {
            'a': {
              'x': [1, 3],
            },
            'b': 2,
          },
          fromCache: false,
          pendingWrites: false,
        ),
        1,
      );
    },
  );
  test('optimistic writes and acknowledgements do not become reads', () {
    final counter = ServerReadEstimate();
    counter.observe({'a': 1}, fromCache: false, pendingWrites: false);
    expect(counter.observe({'a': 2}, fromCache: false, pendingWrites: true), 0);
    expect(
      counter.observe({'a': 2}, fromCache: false, pendingWrites: false),
      0,
    );
    expect(
      counter.observe({'a': 3}, fromCache: false, pendingWrites: false),
      1,
    );
  });
  test(
    'empty query minimum charged once and removals are not assumed billed',
    () {
      final counter = ServerReadEstimate();
      expect(counter.observe({}, fromCache: true, pendingWrites: false), 0);
      expect(counter.observe({}, fromCache: false, pendingWrites: false), 1);
      expect(counter.observe({}, fromCache: false, pendingWrites: false), 0);
      expect(
        counter.observe({'a': 1}, fromCache: false, pendingWrites: false),
        1,
      );
      expect(counter.observe({}, fromCache: false, pendingWrites: false), 0);
    },
  );
}
