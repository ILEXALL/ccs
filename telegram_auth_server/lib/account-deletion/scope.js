const {createHash} = require('node:crypto');

function deletionScope(env = process.env) {
  if (env.ACCOUNT_DELETION_ENABLED === 'true') return {enabled: true, onlyUid: null, stateId: 'round-robin'};
  const uid = env.ACCOUNT_DELETION_TEST_UID || '';
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid)) return {enabled: false, onlyUid: null, stateId: null};
  return {enabled: true, onlyUid: uid, stateId: `test-${createHash('sha256').update(uid).digest('hex')}`};
}
module.exports = {deletionScope};
