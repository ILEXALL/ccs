const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');

function fixture(sourcePath) {
  const records = new Map(Object.entries({
    'users/owner': {country:'Latvia',role:'admin',fcmTokens:['owner-token']},
    'users/alice': {country:'Latvia',fcmTokens:['alice-token']},
    'users/bob': {country:'Latvia',fcmTokens:['bob-token']},
  }));
  const pushes=[];
  let now=100000000;
  function snap(p) {return {exists:records.has(p),id:p.split('/').at(-1),data:()=>records.get(p)};}
  function ref(p) {return {
    get:async()=>snap(p),
    set:async(value,options)=>records.set(p,options?.merge?{...records.get(p),...value}:value),
    create:async value=>{if(records.has(p))throw Object.assign(new Error('exists'),{code:6});records.set(p,value);},
    delete:async()=>records.delete(p),
    update:async value=>records.set(p,{...records.get(p),...value}),
    path:p,
  };}
  let queue=Promise.resolve();
  const db={
    collection:name=>({doc:id=>ref(name+'/'+id),get:async()=>({docs:[...records.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===2).map(snap)})}),
    runTransaction:fn=>{
      const result=queue.then(async()=>{
        const writes=[];
        const result=await fn({get:r=>r.get(),set:(r,v)=>writes.push(()=>r.set(v))});
        for(const write of writes) await write();
        return result;
      });
      queue=result.catch(()=>{});
      return result;
    },
  };
  const firestore=()=>db;
  firestore.FieldValue={serverTimestamp:()=>now,arrayRemove:()=>[]};
  const admin={apps:[{}],firestore,messaging:()=>({sendEachForMulticast:async payload=>{
    pushes.push(payload);return {successCount:payload.tokens.length,responses:payload.tokens.map(()=>({success:true}))};
  }})};
  const source=fs.readFileSync(sourcePath,'utf8')
    .replace("import publications from '../lib/forum-publications.js';", '')
    .replace("import crypto from 'node:crypto';",'')
    .replace("import admin from 'firebase-admin';",'')
    .replace('export default async function handler','async function handler')
    .replaceAll('export async function ', 'async function ');
  const publications = { drainForumPublications() { throw new Error('Outbox draining is outside this delivery fixture'); } };
  const context={publications,crypto,admin,console,process,Date:class extends Date {static now(){return now;}},exports:{}};
  vm.runInNewContext(source+'\nexports.publish = notifyUsersAboutNewSpot;',context);
  async function publish(id,temporary=false,type=temporary?'temporary_event':'new_spot') {
    return context.exports.publish({spotId:id,spot:{name:id,cityCountry:'Riga, Latvia',addedByUid:'owner',isTemporary:temporary},notificationType:type,deliveryKey:'caller-supplied:'+id});
  }
  return {publish,pushes,records,advance:ms=>{now+=ms;},bells:()=>[...records.keys()].filter(p=>p.startsWith('user_notifications/')).length};
}

for (const source of ['../api/push-notification.js','../../api/push-notification.js']) {
  const file=path.resolve(__dirname,source);
  test(`${source}: permanent publications push once per five hours and always reach bell`,async()=>{
    const f=fixture(file);
    await f.publish('first');
    assert.equal(f.pushes.length,2);
    assert.equal(f.bells(),2);
    f.advance(5*60*60*1000-1);
    await f.publish('second');
    assert.equal(f.pushes.length,2);
    assert.equal(f.bells(),4);
    f.advance(1);
    await f.publish('third');
    assert.equal(f.pushes.length,4);
    assert.equal(f.bells(),6);
    assert(f.pushes.every(p=>!p.tokens.includes('owner-token')));
  });
  test(`${source}: every temporary spot pushes without consuming or resetting cooldown`,async()=>{
    const f=fixture(file);
    await f.publish('temp-before',true);
    await f.publish('permanent');
    await f.publish('temp-during',true);
    await f.publish('suppressed');
    assert.equal(f.pushes.length,6);
    assert.equal(f.bells(),8);
    f.advance(5*60*60*1000);
    await f.publish('permanent-after');
    assert.equal(f.pushes.length,8);
  });
  test(`${source}: concurrent permanent publications share one global window`,async()=>{
    const f=fixture(file);
    await Promise.all([f.publish('a'),f.publish('b'),f.publish('c')]);
    assert.equal(f.pushes.length,2);
    assert.equal(f.bells(),6);
  });
  test(`${source}: retries stay deduplicated, including suppressed publications after five hours`,async()=>{
    const f=fixture(file);
    await f.publish('a');
    await f.publish('b');
    await f.publish('temp',true);
    f.advance(6*60*60*1000);
    await f.publish('a');
    await f.publish('b');
    await f.publish('temp',true);
    assert.equal(f.pushes.length,4);
    assert.equal(f.bells(),6);
    await f.publish('new');
    assert.equal(f.pushes.length,6);
  });
  test(`${source}: a caller cannot bypass permanent cooldown with temporary notification type`,async()=>{
    const f=fixture(file);
    await f.publish('a');
    await f.publish('b',false,'temporary_event');
    assert.equal(f.pushes.length,2);
    assert.equal(f.bells(),4);
    assert(f.records.has('user_notifications/new_spot_b_alice'));
  });
}
