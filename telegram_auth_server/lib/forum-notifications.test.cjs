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
    collection:name=>db.collection(p+'/'+name),
  };}
  let queue=Promise.resolve();
  const db={
    collection:name=>({doc:id=>ref(name+'/'+id),get:async()=>({docs:[...records.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===name.split('/').length+1).map(snap)})}),
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
    .replace("import crypto from 'node:crypto';",'')
    .replace("import admin from 'firebase-admin';",'')
    .replace('export default async function handler','async function handler');
  const context={crypto,admin,console,process,Date:class extends Date {static now(){return now;}},exports:{}};
  vm.runInNewContext(source+'\nexports.publish = notifyUsersAboutNewSpot; exports.reply=handleForumReply; exports.legacy=handleForumReplyAdmin; exports.topic=handleForumTopicCreated;',context);
  async function publish(id,temporary=false,type=temporary?'temporary_event':'new_spot') {
    return context.exports.publish({spotId:id,spot:{name:id,cityCountry:'Riga, Latvia',addedByUid:'owner',isTemporary:temporary},notificationType:type,deliveryKey:'caller-supplied:'+id});
  }
  return {...context.exports,publish,pushes,records,advance:ms=>{now+=ms;},bells:()=>[...records.keys()].filter(p=>p.startsWith('user_notifications/')).length};
}


for (const source of ['../api/push-notification.js','../../api/push-notification.js']) {
  const file=path.resolve(__dirname,source);
  function forum() {
    const f=fixture(file);
    f.records.set('users/staff',{role:'moderator',country:'Latvia',moderatorCountryCodes:['LV'],fcmTokens:['staff-token']});
    f.records.set('users/foreign',{country:'Estonia',fcmTokens:['foreign-token']});
    f.records.set('forum_topics/topic',{authorId:'owner',status:'approved',countryCode:'LV',title:'Cars'});
    f.records.set('forum_topics/topic/replies/original',{userId:'bob'});
    f.records.set('forum_topics/topic/replies/msg',{userId:'alice',text:'Hello',replyToMessageId:'original'});
    return f;
  }
  const payload={topicId:'topic',messageId:'msg'};
  const tokens=f=>f.pushes.flatMap(p=>p.tokens).sort();
  test(`${source}: replies push only to author and direct reply target, including legacy events`,async()=>{
    const f=forum();
    await f.legacy('alice',payload);
    await f.reply('alice',payload);
    assert.deepEqual(tokens(f),['bob-token','owner-token']);
    assert.equal(f.bells(),3);
    assert([...f.records.values()].some(v=>v.userId==='staff'&&v.type==='forum_reply'));
  });
  test(`${source}: ordinary messages are bell-only for other participants and staff`,async()=>{
    const f=forum();
    delete f.records.get('forum_topics/topic/replies/msg').replyToMessageId;
    await f.reply('alice',payload);
    assert.deepEqual(tokens(f),['owner-token']);
    assert.equal(f.bells(),3);
  });
  test(`${source}: author and reply target overlap produces one push; self replies produce none`,async()=>{
    const f=forum();
    f.records.get('forum_topics/topic/replies/original').userId='owner';
    await f.reply('alice',payload);
    assert.deepEqual(tokens(f),['owner-token']);
    const g=forum();
    g.records.get('forum_topics/topic/replies/msg').userId='owner';
    g.records.get('forum_topics/topic/replies/original').userId='owner';
    await g.reply('owner',payload);
    assert.deepEqual(tokens(g),[]);
    assert.equal(g.bells(),3);
  });
  test(`${source}: direct targets outside community are retained`,async()=>{
    const f=forum();
    f.records.get('forum_topics/topic/replies/original').userId='foreign';
    await f.reply('alice',{...payload,recipientUserIds:['staff']});
    assert.deepEqual(tokens(f),['foreign-token','owner-token']);
  });
  test(`${source}: pending topics and forged message senders cannot broadcast`,async()=>{
    const f=forum();
    await f.reply('bob',payload);
    f.records.get('forum_topics/topic').status='pending';
    await f.reply('alice',payload);
    await f.topic('owner',payload);
    assert.equal(f.bells(),0);
    assert.equal(f.pushes.length,0);
  });
  test(`${source}: published topics notify all countries once, respecting preferences`,async()=>{
    const f=forum();
    f.records.get('users/bob').commentNotifications=false;
    await f.topic('owner',payload);
    await f.topic('staff',payload);
    assert.deepEqual(tokens(f),['alice-token','foreign-token','staff-token']);
    assert.equal(f.bells(),3);
    await assert.rejects(f.topic('alice',payload));
  });
  test(`${source}: topic broadcast includes users beyond the first 500`,async()=>{
    const f=forum();
    for(let i=0;i<505;i++) f.records.set('users/extra'+i,{fcmTokens:['extra'+i]});
    await f.topic('owner',payload);
    assert.equal(f.bells(),509);
  });
}
