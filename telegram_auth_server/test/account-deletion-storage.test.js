const {test} = require('node:test');
const assert = require('node:assert/strict');
const {storageAdapter} = require('../lib/account-deletion/storage');
const env = {R2_ENDPOINT: 'https://r2.example', R2_ACCESS_KEY_ID: 'test',
  R2_SECRET_ACCESS_KEY: 'test', R2_BUCKET_NAME: 'test', FIREBASE_STORAGE_BUCKET: 'test'};

test('verification is read-only and never returns object names or provider errors', async () => {
  const adapter = storageAdapter(env, {
    s3Client: {send: async command => {
      assert.equal(command.constructor.name, 'ListObjectsV2Command');
      assert.equal(command.input.MaxKeys, 1);
      return {Contents: [{Key: 'private-name'}]};
    }},
    firebaseStorage: {bucket: () => ({
      getFiles: async config => {assert.equal(config.maxResults, 1); return [[{name: 'private-name'}]];},
      getMetadata: async () => [{softDeletePolicy: {retentionDurationSeconds: '604800'}}],
    })},
  });
  assert.deepEqual(await adapter.verifyAccess(), {ok: true, firebaseAbsent: false, r2List: true, firebaseList: true,
    firebaseMetadata: true, firebaseSoftDeleteSeconds: 604800, firebaseRetentionSeconds: 0});
  const failed = storageAdapter(env, {s3Client: {send: async () => {throw Error('secret-provider-details');}},
    firebaseStorage: {bucket: () => ({getFiles: async () => [[]], getMetadata: async () => {throw Error('secret');}})}});
  const result = await failed.verifyAccess();
  assert.equal(result.ok, false);
  assert.equal(result.firebaseSoftDeleteSeconds, null);
  assert.equal(JSON.stringify(result).includes('secret'), false);
});

test('audited missing-bucket opt-in permits only 404, never permission failures', async () => {
  let code = 404;
  const fail = async () => {throw Object.assign(new Error('provider details'), {code});};
  const deps = {s3Client: {send: async () => ({})},
    firebaseStorage: {bucket: () => ({getFiles: fail, getMetadata: fail})}};
  const strict = storageAdapter(env, deps);
  assert.equal((await strict.verifyAccess()).ok, false);
  await assert.rejects(strict.deletePrefixPage('users/test/'));
  const audited = storageAdapter({...env, FIREBASE_STORAGE_ALLOW_MISSING: 'true'}, deps);
  assert.equal((await audited.verifyAccess()).firebaseAbsent, true);
  assert.equal((await audited.verifyAccess()).ok, true);
  assert.equal(await audited.deletePrefixPage('users/test/'), true);
  code = 403;
  assert.equal((await audited.verifyAccess()).ok, false);
  await assert.rejects(audited.deletePrefixPage('users/test/'));
});

test('both R2 and legacy Firebase Storage must be confirmed empty', async () => {
  let r2Objects = ['users/alice/avatar.jpg'], firebaseObjects = ['users/alice/old.jpg'];
  const options = [];
  const adapter = storageAdapter(env, {
    s3Client: {send: async command => {
      if (command.constructor.name === 'ListObjectsV2Command') return {Contents: r2Objects.map(Key => ({Key}))};
      assert.deepEqual(command.input.Delete.Objects, [{Key: 'users/alice/avatar.jpg'}]);
      r2Objects = []; return {};
    }},
    firebaseStorage: {bucket: name => {
      assert.equal(name, 'test');
      return {getFiles: async config => {
        options.push(config);
        return [firebaseObjects.map(name => ({name, delete: async () => {firebaseObjects = [];}}))];
      }};
    }},
  });
  assert.equal(await adapter.deletePrefixPage('users/alice/'), false);
  assert.equal(await adapter.deletePrefixPage('users/alice/'), true);
  assert.equal(options[0].versions, true);
  assert.equal(options[0].autoPaginate, false);
  assert.equal(options[0].prefix, 'users/alice/');
});

test('partial R2 deletion fails the batch and remains retryable', async () => {
  let fail = true;
  const adapter = storageAdapter(env, {
    s3Client: {send: async command => command.constructor.name === 'ListObjectsV2Command'
      ? {Contents: [{Key: 'users/alice/avatar.jpg'}]} : fail ? {Errors: [{Code: 'AccessDenied'}]} : {}},
    firebaseStorage: {bucket: () => ({getFiles: async () => [[]]})},
  });
  await assert.rejects(adapter.deletePrefixPage('users/alice/'), /could not be deleted/);
  fail = false;
  assert.equal(await adapter.deletePrefixPage('users/alice/'), false);
});

test('Firebase Storage permissions failures are not silently treated as empty', async () => {
  const adapter = storageAdapter(env, {
    s3Client: {send: async () => ({})},
    firebaseStorage: {bucket: () => ({getFiles: async () => {throw new Error('Permission denied');}})},
  });
  await assert.rejects(adapter.deletePrefixPage('users/alice/'), /Permission denied/);
  await assert.rejects(adapter.deletePrefixPage('users/'), /Unsafe storage prefix/);
  await assert.rejects(adapter.deletePrefixPage('users/alice/../bob/'), /Unsafe storage prefix/);
});

test('missing legacy-storage configuration prevents accepting deletion', () => {
  assert.throws(() => storageAdapter({...env, FIREBASE_STORAGE_BUCKET: ''}), /FIREBASE_STORAGE_BUCKET/);
});
