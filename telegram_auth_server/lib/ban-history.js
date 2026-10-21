const millis = value => typeof value?.toMillis === 'function' ? value.toMillis() :
  typeof value === 'number' ? value : null;

function activeBan(user, now = Date.now()) {
  const until = millis(user.bannedUntil);
  return user.banned === true && (until === null || until > now);
}

// Merge the legacy profile snapshot with immutable moderation records. Older
// clients did not record every ban, so this is a count of recorded bans only.
function banHistory(user, logs) {
  const bans = logs.filter(l => l.action === 'user_banned').map(l => ({
    bannedAt: millis(l.createdAt), expiresAt: millis(l.bannedUntil),
    reason: l.reason || '', liftedAt: millis(l.liftedAt),
    bannedByUid: l.actorUid || '', bannedBy: l.actorUsername || '',
  }));
  const at = millis(user.bannedAt);
  const until = millis(user.bannedUntil);
  if (at !== null && !bans.some(b => b.bannedAt === at ||
      (until !== null && b.expiresAt === until))) {
    bans.push({ bannedAt: at, expiresAt: until, reason: user.banReason || '', liftedAt: null,
      bannedByUid: user.bannedByUid || '', bannedBy: user.bannedBy || '' });
  }
  for (const ban of bans) {
    if (ban.bannedAt === at || (until !== null && ban.expiresAt === until)) {
      if (!ban.bannedByUid) ban.bannedByUid = user.bannedByUid || '';
      if (!ban.bannedBy && (!ban.bannedByUid || ban.bannedByUid === user.bannedByUid)) {
        ban.bannedBy = user.bannedBy || '';
      }
    }
    const lifts = [ban.liftedAt, ...logs.filter(l => l.action === 'user_unbanned' &&
      millis(l.banStartedAt) === ban.bannedAt).map(l => millis(l.createdAt))];
    if (ban.bannedAt === at && user.banned !== true) lifts.push(millis(user.unbannedAt));
    ban.liftedAt = lifts.filter(t => t !== null && t >= ban.bannedAt).sort((a,b) => a-b)[0] ?? null;
  }
  return bans.sort((a,b) => (b.bannedAt || 0) - (a.bannedAt || 0));
}

module.exports = { millis, activeBan, banHistory };
