// The directory deliberately excludes member identities and message previews.
function ownerUid(chat) {
  return chat.ownerUid || (chat.memberIds || [])[0] || '';
}

function directoryEntry(id, chat, uid, canMonitor, requestStatus = '') {
  return {
    id, name: chat.name || 'Group chat',
    photoUrl: chat.photoUrl || chat.avatarUrl || '',
    description: chat.description || '',
    isMember: (chat.memberIds || []).includes(uid),
    isOwner: ownerUid(chat) === uid,
    canMonitor, requestStatus,
  };
}

function acceptedMemberFields(chat, uid, user) {
  const ids = chat.memberIds || [];
  if (ids.includes(uid)) return {};
  return {
    memberIds: [...ids, uid],
    memberUsernames: [...ids.map((_, i) => (chat.memberUsernames || [])[i] || ''), user.username || 'driver'],
    memberPhotoUrls: [...ids.map((_, i) => (chat.memberPhotoUrls || [])[i] || ''), user.photoUrl || ''],
    hiddenForUserIds: (chat.hiddenForUserIds || []).filter(id => id !== uid),
  };
}

const countryNames = new Map();
for (const locale of ['en', 'ru', 'lv']) {
  const names = new Intl.DisplayNames([locale], { type: 'region' });
  for (const code of ['AL','AM','AU','AT','AZ','BY','BE','BA','BR','BG','CA','CN','HR','CY','CZ','DK','EE','FI','FR','GE','DE','GR','HU','IS','IN','IE','IT','JP','LV','LT','LU','MT','MX','MD','ME','NL','NZ','MK','NO','PL','PT','RO','RU','RS','SK','SI','KR','ES','SE','CH','TR','UA','AE','GB','US']) {
    countryNames.set(code.toLowerCase(), code);
    countryNames.set(names.of(code).toLowerCase(), code);
  }
}
for (const [alias, code] of Object.entries({uk:'GB','great britain':'GB',usa:'US','сша':'US',asv:'US',uae:'AE','оаэ':'AE',aae:'AE','czech republic':'CZ'})) countryNames.set(alias, code);
function countryCode(value) {
  return typeof value === 'string' ? countryNames.get(value.trim().toLowerCase()) || '' : '';
}
function profileCountry(user) {
  return countryCode(user.country) || countryCode(user.countryCode);
}
function directoryCountry(actor, requestedCountry) {
  return actor.role === 'admin' && requestedCountry != null
    ? countryCode(requestedCountry) : profileCountry(actor);
}

module.exports = { ownerUid, directoryEntry, acceptedMemberFields, countryCode, profileCountry, directoryCountry };
