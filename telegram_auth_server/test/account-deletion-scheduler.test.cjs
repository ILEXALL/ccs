const {test} = require('node:test');
const assert = require('node:assert/strict');
const load = () => import('../../tool/account-deletion-scheduler/worker.mjs');

test('verification invokes only the read-only action while deletion is disabled', async t => {
  const {default: worker} = await load();
  t.mock.method(console, 'log', () => {});
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, 'https://ccs-wine.vercel.app/api/account-deletion?action=verify');
    assert.equal(options.redirect, 'manual');
    return {ok: true, json: async () => ({ok: true, mode: 'verify'})};
  });
  await worker.scheduled({}, {ENABLED: 'false', VERIFY_ONLY: 'true', ACCOUNT_DELETION_WORKER_SECRET: 'fixture'});
});

test('verification reports only whitelisted capabilities on failure', async t => {
  const {default: worker} = await load();
  const messages = [];
  t.mock.method(console, 'log', text => messages.push(JSON.parse(text)));
  t.mock.method(globalThis, 'fetch', async () => ({ok: false, status: 503,
    json: async () => ({ok: false, mode: 'verify', r2List: true, private: 'must not log'})}));
  await assert.rejects(worker.scheduled({}, {VERIFY_ONLY: 'true', ACCOUNT_DELETION_WORKER_SECRET: 'fixture'}), /Storage verification failed/);
  assert.equal(messages[0].r2List, true);
  assert.equal(messages[0].firebaseSoftDeleteSeconds, null);
  assert.equal(JSON.stringify(messages).includes('must not log'), false);
});

test('disabled scheduler makes no request; there is no public trigger', async t => {
  const {default: worker} = await load();
  t.mock.method(globalThis, 'fetch', async () => assert.fail('must not fetch'));
  await worker.scheduled({}, {ENABLED: 'false'});
  assert.equal((await worker.fetch()).status, 404);
});

test('scheduler calls only the canonical backend and refuses redirects', async t => {
  const {default: worker} = await load();
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, 'https://ccs-wine.vercel.app/api/account-deletion');
    assert.equal(options.headers.Authorization, 'Bearer fixture-secret');
    assert.equal(options.redirect, 'manual');
    return {ok: true, json: async () => ({ok: true, attempted: 1, pending: false})};
  });
  await worker.scheduled({}, {ENABLED: 'true', ACCOUNT_DELETION_WORKER_SECRET: 'fixture-secret'});
});

test('failed batches fail the scheduler invocation instead of reporting success', async t => {
  const {default: worker} = await load();
  const env = {ENABLED: 'true', ACCOUNT_DELETION_WORKER_SECRET: 'fixture-secret'};
  const fetchMock = t.mock.method(globalThis, 'fetch', async () => ({ok: false, status: 503}));
  await assert.rejects(worker.scheduled({}, env), /HTTP 503/);
  fetchMock.mock.mockImplementation(async () => ({ok: false, status: 302}));
  await assert.rejects(worker.scheduled({}, env), /HTTP 302/);
  fetchMock.mock.mockImplementation(async () => ({ok: true, json: async () => ({ok: false})}));
  await assert.rejects(worker.scheduled({}, env), /did not succeed/);
});
