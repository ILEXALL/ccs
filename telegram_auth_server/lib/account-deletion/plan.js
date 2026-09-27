// Pure deletion policy. No network calls: keep destructive decisions testable.
const ownedFields = ['uid', 'userId', 'senderUid', 'authorId', 'authorUid', 'addedByUid'];
const relationFields = ['fromUid', 'toUid', 'targetUserId', 'reportedUid', 'reporterUid',
  'actorUserId', 'actorUid', 'sourceUserUid', 'recipientUid'];
const sharedRoots = new Set(['users', 'chats', 'app_config', 'partners', 'admin_rewards']);
const systemRoots = new Set(['account_deletions', 'account_deletion_receipts']);
const plain = value => value && Object.getPrototypeOf(value) === Object.prototype;

const identityField = field => /(?:uid|uids|userId|userIds|memberIds|moderatorIds|friendIds|authorId)$/i.test(field);
function containsUid(value, uid, field = '') {
  if (value === uid) return identityField(field);
  if (Array.isArray(value)) return value.some(item => containsUid(item, uid, field));
  return plain(value) && Object.entries(value).some(([key, item]) => key === uid || containsUid(item, uid, key));
}

// Exact UID references only. Never substring-match ordinary text or another UID.
function scrub(value, uid, field = '') {
  if (value === uid && identityField(field)) return '';
  if (Array.isArray(value)) return value.filter(item => item !== uid || !identityField(field)).map(item => scrub(item, uid, field));
  if (!plain(value)) return value;
  return Object.fromEntries(Object.entries(value).filter(([key]) => key !== uid)
    .map(([key, item]) => [key, scrub(item, uid, key)]));
}

function planDocument(path, data, account) {
  const {uid, username, replyWasDeleted} = account;
  const parts = path.split('/');
  const root = parts[0], collection = parts.at(-2), id = parts.at(-1);
  if (systemRoots.has(root)) return {action: 'skip'};
  if (root === 'users' && parts[1] === uid) return {action: 'delete'};
  if (root === 'telegram_login_sessions' && uid === `telegram_${data.telegram?.id}`) return {action: 'delete'};
  const owns = ownedFields.some(key => data[key] === uid);
  const related = relationFields.some(key => data[key] === uid);
  if ((root.endsWith('_notifications') || ['user_reports', 'moderation_logs', 'xp_admin_audit', 'push_deliveries'].includes(root)) && containsUid(data, uid)) {
    return {action: 'delete'};
  }
  if (!sharedRoots.has(root) && (owns || related || id === uid ||
      (['friendships', 'blocked_users'].includes(root) && containsUid(data, uid)))) {
    return {action: 'delete'};
  }
  if (['messages', 'replies', 'join_requests'].includes(collection) && (owns || id === uid)) {
    return {action: 'delete'};
  }
  if (root === 'spots' && data.ownerUid === uid) return {action: 'delete'};
  let changed = containsUid(data, uid);
  const next = scrub(data, uid);
  if (root === 'chats' && parts.length === 2) {
    const ids = Array.isArray(data.memberIds) ? data.memberIds : [];
    if (ids.includes(uid)) {
      const indexes = ids.map((id, index) => id === uid ? -1 : index).filter(index => index >= 0);
      next.memberIds = indexes.map(index => ids[index]);
      for (const field of ['memberUsernames', 'memberPhotoUrls']) {
        next[field] = indexes.map(index => data[field]?.[index] || '');
      }
      if (data.ownerUid === uid) next.ownerUid = next.memberIds[0] || '';
    }
    if (data.lastSenderUid === uid) {
      next.lastMessage = ''; next.lastSenderUid = ''; next.lastSenderUsername = '';
    }
  }
  // Reply previews duplicate message text and photographs outside the source row.
  if (replyWasDeleted || (username && data.replyToUsername === username)) {
    for (const key of Object.keys(next).filter(key => key.startsWith('replyTo'))) next[key] = '';
    changed = true;
  }
  // Shared records may contain media originally uploaded by this account.
  const cleanMedia = value => {
    if (typeof value === 'string' && /^(https?:|gs:)/.test(value) &&
        [uid, encodeURIComponent(uid)].some(id => value.includes(`/users/${id}/`) || value.includes(`/garage/${id}/`))) {
      changed = true; return '';
    }
    if (Array.isArray(value)) return value.map(cleanMedia);
    if (plain(value)) return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, cleanMedia(item)]));
    return value;
  };
  const cleaned = cleanMedia(next);
  return changed ? {action: 'replace', data: cleaned} : {action: 'skip'};
}

module.exports = {planDocument, systemRoots, containsUid};
