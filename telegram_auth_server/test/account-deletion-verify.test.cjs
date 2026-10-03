const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('authenticated verification works while disabled without touching queue, auth or database', async () => {
  let checks = 0;
  const module = {exports: {}};
  const requireStub = name => {
    if (name === 'node:crypto') return require(name);
    if (name.endsWith('/scope')) return require('../lib/account-deletion/scope');
    if (name.endsWith('/firebase-admin')) return {admin: {storage: () => ({})}};
    if (name.endsWith('/storage')) return {storageAdapter: () => ({verifyAccess: async () => {checks++; return {ok: true};}})};
    if (['/worker', '/list-page', '/queue'].some(suffix => name.endsWith(suffix))) return {};
    throw Error('Unexpected dependency');
  };
  new Function('require', 'module', 'process', fs.readFileSync(path.resolve(__dirname, '../handlers/account-deletion.js'), 'utf8'))(
    requireStub, module, {env: {ACCOUNT_DELETION_ENABLED: 'false', ACCOUNT_DELETION_WORKER_SECRET: 'fixture'}});
  const request = async authorization => {
    const res = {code: 200, setHeader() {}, status(code) {this.code = code; return this;}, json(data) {this.data = data; return this;}};
    await module.exports({method: 'GET', headers: {authorization}, query: {action: 'verify'}}, res);
    return res;
  };
  assert.equal((await request('Bearer wrong')).code, 401);
  assert.equal(checks, 0);
  assert.deepEqual((await request('Bearer fixture')).data, {mode: 'verify', ok: true});
  assert.equal(checks, 1);
});
