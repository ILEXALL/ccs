const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8189';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
const project = 'demo-ccs-spot-likes';
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const token = uid => `${Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({sub:uid,user_id:uid,aud:project,iss:`https://securetoken.google.com/${project}`,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,firebase:{sign_in_provider:'custom'}})).toString('base64url')}.`;
function value(v) {
  if (typeof v==='string') return {stringValue:v};
  if (typeof v==='boolean') return {booleanValue:v};
  if (typeof v==='number') return {integerValue:String(v)};
  if (Array.isArray(v)) return {arrayValue:{values:v.map(value)}};
  if (v===null) return {nullValue:null};
  return {mapValue:{fields:fields(v)}};
}
const fields = obj => Object.fromEntries(Object.entries(obj).map(([k,v])=>[k,value(v)]));
async function request(path, uid, method='GET', obj) {
  const masks=obj?Object.keys(obj).map(k=>'updateMask.fieldPaths='+encodeURIComponent(k)).join('&'):'';
  return fetch(`${base}/${path}${masks?'?'+masks:''}`,{method,headers:{authorization:'Bearer '+(uid==='owner'?'owner':token(uid)),'content-type':'application/json'},body:obj?JSON.stringify({fields:fields(obj)}):undefined});
}
async function seed(path,obj) {const res=await request(path,'owner','PATCH',obj);assert.equal(res.status,200,await res.text());}

test.before(async () => {
  const content = fs.readFileSync(require('node:path').resolve(__dirname, '../../firestore.rules'), 'utf8');
  const res = await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: {'content-type': 'application/json'},
    body: JSON.stringify({rules: {files: [{name: 'firestore.rules', content}]}}),
  });
  assert.equal(res.status, 200, await res.text());
  for (const uid of ['driver', 'other', 'banned']) {
    await seed('users/' + uid, {uid, role: 'user', country: 'Latvia', verified: false,
      deleted: false, banned: uid === 'banned'});
  }
  await seed('spots/public', {name: 'Public spot', visibility: 'public',
    status: 'approved', addedByUid: 'other', verifiedOnly: false, likeCount: 0,
    commentCount: 0, sharedGroupIds: [], sharedGroups: []});
  await seed('spots/private', {name: 'Private spot', visibility: 'group',
    status: 'approved', addedByUid: 'other', isTemporary: true, sharedGroupIds: ['secret']});
  await seed('spot_likes/private_other', {spotId: 'private', userId: 'other'});
});

test('first like, unlike and re-like can read absence and commit atomically', async () => {
  for (const liked of [true, false, true]) {
    const begin = await fetch(base + ':beginTransaction', {
      method: 'POST', headers: {authorization: 'Bearer ' + token('driver'),
        'content-type': 'application/json'}, body: '{}',
    });
    assert.equal(begin.status, 200);
    const {transaction} = await begin.json();
    const root = `projects/${project}/databases/(default)/documents`;
    const read = await fetch(base + ':batchGet', {
      method: 'POST', headers: {authorization: 'Bearer ' + token('driver'),
        'content-type': 'application/json'},
      body: JSON.stringify({transaction, documents: [root + '/spot_likes/public_driver', root + '/spots/public']}),
      signal: AbortSignal.timeout(10000),
    });
    assert.equal(read.status, 200);
    const docs = await read.json();
    const like = docs.find(doc => (doc.found?.name || doc.missing).endsWith('/spot_likes/public_driver'));
    assert.equal(Boolean(like.missing), liked);
    const likeWrite = liked ? {update: {name: root + '/spot_likes/public_driver',
      fields: fields({spotId: 'public', userId: 'driver', targetType: 'spot',
        spotName: 'Public spot', spotOwnerUid: 'other', username: 'Driver'})},
      updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}]}
      : {delete: root + '/spot_likes/public_driver'};
    const commit = await fetch(base + ':commit', {
      method: 'POST', headers: {authorization: 'Bearer ' + token('driver'),
        'content-type': 'application/json'},
      body: JSON.stringify({transaction, writes: [likeWrite, {
        update: {name: root + '/spots/public', fields: fields({likeCount: liked ? 1 : 0})},
        updateMask: {fieldPaths: ['likeCount']},
        updateTransforms: [{fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}],
      }]}),
    });
    assert.equal(commit.status, 200, await commit.text());
    const saved = await request('spots/public', 'driver');
    assert.equal((await saved.json()).fields.likeCount.integerValue, liked ? '1' : '0');
  }
});

test('absence permission does not expose existing private likes or allow private writes', async () => {
  const read = await request('spot_likes/private_other', 'driver');
  assert.equal(read.status, 403, await read.text());
  const write = await request('spot_likes/private_driver', 'driver', 'PATCH',
    {spotId: 'private', userId: 'driver', targetType: 'spot'});
  assert.equal(write.status, 403, await write.text());
});

test('banned and anonymous clients cannot check missing like documents', async () => {
  const banned = await request('spot_likes/public_banned', 'banned');
  assert.equal(banned.status, 403, await banned.text());
  const anonymous = await fetch(base + '/spot_likes/public_anonymous');
  assert.equal(anonymous.status, 403, await anonymous.text());
});

test('own-like queries still work', async () => {
  const res = await fetch(base + ':runQuery', {method: 'POST',
    headers: {authorization: 'Bearer ' + token('driver'), 'content-type': 'application/json'},
    body: JSON.stringify({structuredQuery: {from: [{collectionId: 'spot_likes'}],
      where: {fieldFilter: {field: {fieldPath: 'userId'}, op: 'EQUAL', value: value('driver')}}}}),
  });
  assert.equal(res.status, 200, await res.text());
});
