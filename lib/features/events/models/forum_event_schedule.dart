import 'package:ccs_app/core/firestore/firebase_values.dart';
import 'package:ccs_app/core/localization/ccs_text.dart';
import 'package:ccs_app/shared/utils/date_formatting.dart';

String localizedForumEventDescription(Map<String, dynamic> topic) {
  var description = stringFromFirebase(topic['description'], '');
  final start = timestampMillisFromFirebase(topic['temporarySpotStartsAt']);
  final end = timestampMillisFromFirebase(topic['temporarySpotExpiresAt']);
  if (start <= 0 && end <= 0) return description;
  // Replace at most the two generated suffix paragraphs; leave original prose intact.
  String withoutDateSuffix(String text, String labels) => text.replaceFirst(
    RegExp(
      '\\n\\n(?:$labels): \\d{2}\\.\\d{2} \\d{2}:\\d{2}'
      r'$',
    ),
    '',
  );
  if (end > 0) {
    description = withoutDateSuffix(
      description,
      'Ends at|Beidzas|Заканчивается',
    );
  }
  if (start > 0) {
    description = withoutDateSuffix(description, 'Starts at|Sākas|Начинается');
  }
  return [
    description,
    if (start > 0)
      '${trText('Starts at')}: ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(start))}',
    if (end > 0)
      '${trText('Ends at')}: ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(end))}',
  ].where((part) => part.isNotEmpty).join('\n\n');
}
