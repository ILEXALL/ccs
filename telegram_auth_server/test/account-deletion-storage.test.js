const {test} = require('node:test');
const assert = require('node:assert/strict');
const {storageAdapter} = require('../lib/account-deletion/storage');
const env = {R2_ENDPOINT: 'https://storage.example.test', R2_ACCESS_KEY_ID: 'test',
  R2_SECRET_ACCESS_KEY: 'test', R2_BUCKET_NAME: 'test-bucket'};

test('R2 deletion retries partial errors and only completes after an empty listing', async () => {
  const calls = [];
  const responses = [
    {Contents: [{Key: 'users/alice/a'}, {Key: 'users/alice/b'}], IsTruncated: true},
    {Errors: [{Key: 'users/alice/b', Code: 'InternalError'}]},
    {Contents: [{Key: 'users/alice/b'}]}, {}, {},
  ];
  const media = storageAdapter(env, {client: {send: async command => {
    calls.push(command.input);
    return responses.shift();
  }}});
  await assert.rejects(media.deletePrefixPage('users/alice/'), /could not be deleted/);
  assert.equal(await media.deletePrefixPage('users/alice/'), false);
  assert.equal(await media.deletePrefixPage('users/alice/'), true);
  assert.deepEqual(calls[1].Delete.Objects, [{Key: 'users/alice/a'}, {Key: 'users/alice/b'}]);
  assert.deepEqual(calls[3].Delete.Objects, [{Key: 'users/alice/b'}]);
  assert.ok(calls.filter(call => call.Prefix).every(call => call.Prefix === 'users/alice/' && !call.ContinuationToken));
});

test('R2 cleanup rejects broad or ambiguous prefixes before contacting storage', async () => {
  const media = storageAdapter(env, {client: {send: () => assert.fail('unsafe storage call')}});
  for (const prefix of ['users/', 'users/alice', 'users/alice/../', '/users/alice/', 'users/alice/child/', 'other/alice/']) {
    await assert.rejects(media.deletePrefixPage(prefix), /Unsafe storage prefix/);
  }
});

test('R2 network failure remains retryable instead of claiming completion', async () => {
  const media = storageAdapter(env, {client: {send: async () => {throw new Error('unavailable');}}});
  await assert.rejects(media.deletePrefixPage('spots/synthetic/'), /unavailable/);
  assert.throws(() => storageAdapter({}), /configuration missing/);
});
