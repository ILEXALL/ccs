/// Collect all cursor pages before the caller applies global sorting/filtering.
Future<List<T>> collectQueryPages<T>({
  required int pageSize,
  required Future<List<T>> Function(T? cursor, int pageSize) readPage,
}) async {
  if (pageSize < 1) throw ArgumentError.value(pageSize, 'pageSize');
  final results = <T>[];
  T? cursor;
  while (true) {
    final page = await readPage(cursor, pageSize);
    results.addAll(page);
    if (page.length < pageSize) return results;
    cursor = page.last;
  }
}
