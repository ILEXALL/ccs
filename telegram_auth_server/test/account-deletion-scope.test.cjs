const {test} = require('node:test');
const assert = require('node:assert/strict');
const {deletionScope} = require('../lib/account-deletion/scope');
const fs = require('node:fs');
const path = require('node:path');

test('restricted scope is explicit, valid, and has separate scheduler health', () => {
  for (const uid of ['', '../other', 'a/b', 'x'.repeat(129)]) assert.equal(deletionScope({ACCOUNT_DELETION_TEST_UID: uid}).enabled, false);
  const scope = deletionScope({ACCOUNT_DELETION_ENABLED: 'false', ACCOUNT_DELETION_TEST_UID: 'alice'});
  assert.equal(scope.onlyUid, 'alice'); assert.match(scope.stateId, /^test-[a-f0-9]{64}$/);
  assert.equal(deletionScope({ACCOUNT_DELETION_ENABLED: 'true', ACCOUNT_DELETION_TEST_UID: 'alice'}).onlyUid, null);
});

test('test scope uses authenticated UID, never a username or request UID', async () => {
  let tokenUid = 'bob', reads = 0;
  const module = {exports: {}};
  const requireStub = name => {
    if (name === 'node:crypto') return require(name);
    if (name.endsWith('/scope')) return {deletionScope};
    if (name.endsWith('/firebase-admin')) return {db: {collection: () => {reads++; throw Error('must not read');}},
      admin: {storage: () => ({}), auth: () => ({verifyIdToken: async () => ({uid: tokenUid, auth_time: 0})})}};
    if (name.endsWith('/storage')) return {storageAdapter: () => ({})};
    if (['/worker', '/queue', '/list-page'].some(s => name.endsWith(s))) return {};
    throw Error('Unexpected dependency');
  };
  new Function('require', 'module', 'process', fs.readFileSync(path.resolve(__dirname, '../handlers/account-deletion.js'), 'utf8'))(
    requireStub, module, {env: {ACCOUNT_DELETION_ENABLED: 'false', ACCOUNT_DELETION_TEST_UID: 'alice', CRON_SECRET: 'fixture'}});
  const request = async () => {
    const res = {code: 200, setHeader() {}, status(code) {this.code = code; return this;}, json(data) {this.data = data; return this;}};
    await module.exports({method: 'POST', headers: {authorization: 'Bearer fixture'}, body: {uid: 'alice', username: 'alice', confirmation: 'DELETE'}}, res);
    return res;
  };
  assert.equal((await request()).code, 503);
  tokenUid = 'alice';
  assert.equal((await request()).code, 401); // correct account still requires recent sign-in
  assert.equal(reads, 0);
});
