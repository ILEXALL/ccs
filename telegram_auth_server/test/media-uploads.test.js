const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateUpload, createUploadHandler, CACHE_CONTROL} = require('../lib/media-uploads');

test('upload paths are rejected rather than normalized to another object', () => {
  for (const path of ['users/a/../b.jpg', '/users/a/a.jpg', 'users/a//a.jpg',
    'users/a/', 'users/a/./x.jpg', 'users/a/%2e%2e/x', 'users/a\\x.jpg', 'users/a']) {
    assert.throws(() => validateUpload({path, contentType: 'image/jpeg'}), {status: 400});
  }
  assert.equal(validateUpload({path: 'spots/draft/gallery/1.jpg', contentType: 'image/jpeg',
    cacheControl: 'public, max-age=31536000'}).cacheControl, CACHE_CONTROL);
  assert.throws(() => validateUpload({path: 'users/a/a.svg', contentType: 'image/svg+xml'}), {status: 400});
});

test('old tokenless upload requests fail before storage or database access', async () => {
  const never = () => assert.fail('Unauthenticated request reached a dependency');
  const handler = createUploadHandler({auth: {verifyIdToken: never}, db: {}, sign: never});
  const res = {setHeader() {}, status(code) {this.code = code; return this;}, json(data) {this.data = data;}};
  await handler({method: 'POST', headers: {}, body: {path: 'users/a/a.jpg'}}, res);
  assert.equal(res.code, 401);
  assert.deepEqual(res.data, {error: 'Sign in required'});
});

test('revoked tokens cannot issue an upload URL', async () => {
  const handler = createUploadHandler({auth: {verifyIdToken: async (_, revoked) => {
    assert.equal(revoked, true); throw new Error('revoked');
  }}, db: {}, sign: () => assert.fail('Signed a revoked upload')});
  const res = {setHeader() {}, status(code) {this.code = code; return this;}, json() {}};
  await handler({method: 'POST', headers: {authorization: 'Bearer old'}, body: {}}, res);
  assert.equal(res.code, 401);
});
