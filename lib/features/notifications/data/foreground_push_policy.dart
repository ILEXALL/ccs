// APNs messages can omit the FCM sent timestamp. Arrival via onMessage is
// sufficient for those messages; known old messages remain suppressed.
bool foregroundPushIsCurrent(DateTime? sentTime, DateTime launchedAt) =>
    sentTime == null || sentTime.isAfter(launchedAt);
