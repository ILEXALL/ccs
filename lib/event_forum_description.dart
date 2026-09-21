/// The public forum permits 2,000 characters, including generated metadata.
/// Keep dates/location visible; the original event description is untouched.
String eventForumDescription(String description, List<String> metadata) {
  const limit = 2000;
  final details = metadata.where((part) => part.trim().isNotEmpty).join('\n\n');
  final body = description.trim();
  final suffix = details.isEmpty ? '' : '\n\n$details';
  if (body.isEmpty && details.isEmpty) return 'Event.';
  if (body.length + suffix.length <= limit) return '$body$suffix'.trim();
  if (suffix.length >= limit) return _preview(details, limit);
  return '${_preview(body, limit - suffix.length)}$suffix';
}

String _preview(String value, int limit) {
  if (value.length <= limit) return value;
  if (limit <= 1) return '…';
  var end = limit - 1;
  // Do not split a UTF-16 surrogate pair (emoji).
  final last = value.codeUnitAt(end - 1);
  if (last >= 0xd800 && last <= 0xdbff) end--;
  return '${value.substring(0, end).trimRight()}…';
}
