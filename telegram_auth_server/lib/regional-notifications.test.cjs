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
    collection:name=>{
      const query=(field,expected)=>({get:async()=>({docs:[...records.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===name.split('/').length+1&&(!field||records.get(p)[field]===expected)).map(snap)})});
      return {doc:id=>ref(name+'/'+id),get:query().get,where:(field,op,expected)=>query(field,expected)};
    },
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
  vm.runInNewContext(source+'\nexports.publish = notifyUsersAboutNewSpot; exports.pending=handleForumTopicPending; exports.global=handleGlobalChatAdmin; exports.spot=handleSpotPendingReview;',context);
  async function publish(id,temporary=false,type=temporary?'temporary_event':'new_spot') {
    return context.exports.publish({spotId:id,spot:{name:id,cityCountry:'Riga, Latvia',addedByUid:'owner',isTemporary:temporary},notificationType:type,deliveryKey:'caller-supplied:'+id});
  }
  return {...context.exports,publish,pushes,records,advance:ms=>{now+=ms;},bells:()=>[...records.keys()].filter(p=>p.startsWith('user_notifications/')).length};
}


for(const source of ['../api/push-notification.js','../../api/push-notification.js']) {
  const file=path.resolve(__dirname,source);
  function setup() {
    const f=fixture(file);
    f.records.set('users/ee',{role:'moderator',country:'Latvia',moderatorCountryCodes:['EE'],fcmTokens:['ee-token']});
    f.records.set('users/lv',{role:'moderator',country:'Estonia',moderatorCountryCodes:['LV'],fcmTokens:['lv-token']});
    f.records.set('users/empty',{role:'moderator',country:'Estonia',globalModerator:true,fcmTokens:['empty-token']});
    f.records.set('users/community',{role:'user',globalModerator:true,moderatorCountryCodes:['EE'],fcmTokens:['community-token']});
    f.records.set('forum_topics/topic',{status:'pending',authorId:'alice',title:'Test',countryCode:'EE'});
    f.records.set('global_chat/msg',{userId:'alice',text:'Hi',countryCode:'EE'});
    f.records.set('spots/spot',{addedByUid:'alice',status:'pending',name:'Test',countryCode:'EE'});
    return f;
  }
  const tokens=f=>f.pushes.flatMap(p=>p.tokens).sort();
  test(`${source}: forum review alerts use assigned country, not home country or payload`,async()=>{
    const f=setup();
    await f.pending('alice',{topicId:'topic',countryCode:'LV',recipientUserIds:['lv','empty']});
    assert.deepEqual(tokens(f),['community-token','ee-token','owner-token']);
    assert.equal([...f.records.keys()].filter(p=>p.startsWith('admin_notifications/')).length,3);
    assert([...f.records.values()].filter(v=>v.type==='forum_topic_pending').every(v=>v.data.countryCode==='EE'));
  });
  test(`${source}: global staff alerts cannot target foreign or unassigned moderators`,async()=>{
    const f=setup();
    await f.global('alice',{messageId:'msg',countryCode:'LV',recipientUserIds:['ee','lv','empty','owner','community']});
    assert.deepEqual(tokens(f),['community-token','ee-token','owner-token']);
  });
  test(`${source}: spot review alerts reject forged recipients and country`,async()=>{
    const f=setup();
    await f.spot('alice',{spotId:'spot',countryCode:'LV',recipientUserIds:['ee','lv','empty','owner','community']});
    assert.deepEqual(tokens(f),['ee-token','owner-token']);
  });
  test(`${source}: missing spot country is admin-only; legacy community belongs to LV`,async()=>{
    const f=setup();
    delete f.records.get('spots/spot').countryCode;
    f.records.get('spots/spot').cityCountry='Tallinn, Estonia';
    await f.spot('alice',{spotId:'spot',recipientUserIds:['ee','owner']});
    assert.deepEqual(tokens(f),['owner-token']);
    delete f.records.get('forum_topics/topic').countryCode;
    await f.pending('alice',{topicId:'topic'});
    assert.deepEqual(tokens(f),['lv-token','owner-token','owner-token']);
  });
}
