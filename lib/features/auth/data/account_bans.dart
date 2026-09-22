import 'package:ccs_app/core/firestore/firebase_values.dart'
    show nullableTimestampMillisFromFirebase, stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show trText;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;

bool userBanIsActive(Map<String, dynamic>? data) {
  if (data?['banned'] != true) {
    return false;
  }

  final untilMillis = nullableTimestampMillisFromFirebase(data?['bannedUntil']);
  return untilMillis == null ||
      untilMillis > DateTime.now().millisecondsSinceEpoch;
}

String userBanReasonFromFirebase(Map<String, dynamic>? data) {
  final reason = stringFromFirebase(data?['banReason'], '').trim();
  if (reason.isNotEmpty) {
    return reason;
  }

  return stringFromFirebase(data?['bannedReason'], '').trim();
}

String userBanLabel({required bool banned, required int? bannedUntilMillis}) {
  if (!banned) {
    return trText('Active');
  }

  if (bannedUntilMillis == null) {
    return trText('Banned');
  }

  if (bannedUntilMillis <= DateTime.now().millisecondsSinceEpoch) {
    return trText('Ban expired');
  }

  return '${trText('Banned until')} ${formatShortDateTime(DateTime.fromMillisecondsSinceEpoch(bannedUntilMillis))}';
}
