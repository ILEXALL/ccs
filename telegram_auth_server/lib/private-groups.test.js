const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const helpers = require('./private-groups');

function fixture() {
  const data = new Map(Object.entries({
    'users/owner': { username: 'owner', country: 'Latvia' }, 'users/alice': { username: 'alice', country: 'Latvia', photoUrl: 'alice.jpg' },
    'users/bob': { username: 'bob', country: 'Latvia' }, 'users/staff': { role: 'moderator', country: 'Latvia' },
    'chats/group': { isGroup: true, isPrivate: true, ownerUid: 'owner', name: 'Private', memberIds: ['owner'], memberUsernames: ['owner'], lastMessage: 'secret' },
    'chats/direct': { isGroup: false, memberIds: ['owner', 'bob'], lastMessage: 'secret direct' },
  }));
  function ref(p) { return { path: p, id: p.split('/').at(-1), collection: name => collection(p+'/'+name), get: async () => snap(p) }; }
  function snap(p) { return { exists: data.has(p), data: () => structuredClone(data.get(p)), id: p.split('/').at(-1), ref: ref(p) }; }
  function collection(p) { return {
    doc: id => ref(p+'/'+id),
    where: (key, op, value) => ({ get: async () => ({ docs: [...data.keys()].filter(k => k.startsWith(p+'/') && k.split('/').length === p.split('/').length+1 && data.get(k)[key] === value).map(snap) }) }),
  }; }
  let queue = Promise.resolve();
  const db = { collection, getAll: (...refs) => Promise.resolve(refs.map(r => snap(r.path))), runTransaction: callback => {
    const result = queue.then(async () => {
      const writes = [];
      const tx = { get: r => Promise.resolve(snap(r.path)),
        create: (r,v) => { assert(!data.has(r.path)); writes.push(() => data.set(r.path,v)); },
        update: (r,v) => writes.push(() => data.set(r.path,{...data.get(r.path),...v})),
        set: (r,v) => writes.push(() => data.set(r.path,v)),
      };
      const result = await callback(tx);
      writes.forEach(write => write());
      return result;
    });
    queue = result.catch(() => {});
    return result;
  } };
  const admin = { auth: () => ({ verifyIdToken: async uid => ({ uid }) }), firestore: { FieldValue: { serverTimestamp: () => 123 } } };
  const context = { module: { exports: {} }, console, require: name => name === '../lib/firebase-admin' ? {admin, db} : helpers };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../api/private-groups.js'),'utf8'),context);
  async function call(uid, body) {
    const res = { setHeader() {}, status(code) { this.code=code; return this; }, json(body) { this.body=body; } };
    await context.module.exports({ method: 'POST', headers: {authorization: 'Bearer '+uid}, body },res);
    return JSON.parse(JSON.stringify({code:res.code,body:res.body}));
  }
  return { data, call };
}

test('directory exposes existing private groups without messages or membership identities', async () => {
  const {call} = fixture();
  const result = await call('alice',{action:'directory'});
  assert.equal(result.body.groups.length,1);
  const group = result.body.groups[0];
  assert.equal(group.isMember,false);
  assert.equal(group.canMonitor,false);
  for (const key of ['memberIds','lastMessage','ownerUid']) assert.equal(group[key],undefined);
});
test('staff can monitor without membership', async () => {
  const {call,data} = fixture();
  assert.equal((await call('staff',{action:'directory'})).body.groups[0].canMonitor,true);
  assert.deepEqual(data.get('chats/group').memberIds,['owner']);
});
test('concurrent duplicate requests create one notification and one permanent request', async () => {
  const {call,data} = fixture();
  const result = await Promise.all([call('alice',{action:'request',chatId:'group'}),call('alice',{action:'request',chatId:'group'})]);
  assert(result.every(r => r.code===200));
  assert.equal([...data.keys()].filter(k=>k.startsWith('user_notifications/')).length,1);
  assert.equal(data.get('user_notifications/group_request_group_alice').userId,'owner');
});
test('only the owner can list or decide requests, including staff', async () => {
  const {call} = fixture();
  await call('alice',{action:'request',chatId:'group'});
  for(const uid of ['alice','bob','staff']) {
    assert.equal((await call(uid,{action:'requests',chatId:'group'})).code,403);
    assert.equal((await call(uid,{action:'decide',chatId:'group',requesterUid:'alice',decision:'accepted'})).code,403);
  }
});
test('acceptance adds aligned member fields exactly once', async () => {
  const {call,data} = fixture();
  await call('alice',{action:'request',chatId:'group'});
  const body = {action:'decide',chatId:'group',requesterUid:'alice',decision:'accepted'};
  await Promise.all([call('owner',body),call('owner',body)]);
  const chat = data.get('chats/group');
  assert.deepEqual(Array.from(chat.memberIds),['owner','alice']);
  assert.deepEqual(Array.from(chat.memberPhotoUrls),['','alice.jpg']);
  assert.equal(data.get('chats/group/join_requests/alice').status,'accepted');
});
test('rejection prevents all later requests and never adds membership', async () => {
  const {call,data} = fixture();
  await call('alice',{action:'request',chatId:'group'});
  await call('owner',{action:'decide',chatId:'group',requesterUid:'alice',decision:'rejected'});
  assert.equal((await call('alice',{action:'request',chatId:'group'})).body.status,'rejected');
  assert.deepEqual(data.get('chats/group').memberIds,['owner']);
});
test('new owner can decide pending requests; former owner cannot', async () => {
  const {call,data} = fixture();
  await call('alice',{action:'request',chatId:'group'});
  data.get('chats/group').ownerUid='bob';
  const body={action:'decide',chatId:'group',requesterUid:'alice',decision:'accepted'};
  assert.equal((await call('owner',body)).code,403);
  assert.equal((await call('bob',body)).code,200);
});
test('invalid groups, current members and banned applicants cannot request', async () => {
  const {call,data} = fixture();
  assert.equal((await call('alice',{action:'request',chatId:'direct'})).code,404);
  assert.equal((await call('owner',{action:'request',chatId:'group'})).code,409);
  data.get('users/alice').banned=true;
  assert.equal((await call('alice',{action:'request',chatId:'group'})).code,403);
});
test('failed acceptance leaves request pending and writes no decision', async () => {
  const {call,data} = fixture();
  await call('alice',{action:'request',chatId:'group'});
  data.get('users/alice').deleted=true;
  assert.equal((await call('owner',{action:'decide',chatId:'group',requesterUid:'alice',decision:'accepted'})).code,409);
  assert.equal(data.get('chats/group/join_requests/alice').status,'pending');
  assert.equal(data.has('user_notifications/group_decision_group_alice'),false);
});

test('directory uses profile country, ignores user and moderator overrides', async () => {
  const {call,data} = fixture();
  data.set('chats/lithuania', {isGroup:true,isPrivate:true,countryCode:'LT',memberIds:['bob'],name:'LT group'});
  for (const uid of ['alice','staff']) {
    const result = await call(uid,{action:'directory',countryCode:'LT'});
    assert.equal(result.body.countryCode,'LV');
    assert.deepEqual(result.body.groups.map(g=>g.id),['group']);
  }
  data.get('users/alice').country='Lietuva';
  const changed = await call('alice',{action:'directory'});
  assert.deepEqual(changed.body.groups.map(g=>g.id),['lithuania']);
});
test('only admins can select another country', async () => {
  const {call,data} = fixture();
  data.get('users/staff').role='admin';
  data.set('chats/lithuania', {isGroup:true,isPrivate:true,countryCode:'LT',memberIds:['bob'],name:'LT group'});
  const result=await call('staff',{action:'directory',countryCode:'LT'});
  assert.equal(result.body.countryCode,'LT');
  assert.deepEqual(result.body.groups.map(g=>g.id),['lithuania']);
});
test('legacy group country is assigned once and remains after owner moves', async () => {
  const {call,data} = fixture();
  await call('alice',{action:'directory'});
  assert.equal(data.get('chats/group').countryCode,'LV');
  data.get('users/owner').country='Lithuania';
  assert.equal((await call('alice',{action:'directory'})).body.groups.length,1);
  assert.equal(data.get('chats/group').countryCode,'LV');
});
test('cross-country requests are rejected without creating notifications', async () => {
  const {call,data} = fixture();
  data.get('users/alice').country='Lithuania';
  assert.equal((await call('alice',{action:'request',chatId:'group'})).code,403);
  assert.equal(data.has('chats/group/join_requests/alice'),false);
});
test('public group IDs are also filtered and missing country fails closed', async () => {
  const {call,data} = fixture();
  data.set('chats/public-lt',{isGroup:true,isPrivate:false,countryCode:'LT',memberIds:['alice']});
  assert.deepEqual((await call('alice',{action:'directory'})).body.visibleGroupIds,['group']);
  data.get('users/alice').country='';
  assert.equal((await call('alice',{action:'directory'})).code,400);
});
