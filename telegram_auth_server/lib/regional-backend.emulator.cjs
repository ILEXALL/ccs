const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {createRequire}=require('node:module');
const path=require('node:path');
const repo=path.resolve(__dirname, '../..');
const host=process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8189';
if(!/^(localhost|127\.0\.0\.1):\d+$/.test(host)) throw new Error('Local emulator required');
process.env.FIRESTORE_EMULATOR_HOST=host;
const req=createRequire(path.join(repo,'telegram_auth_server/api/moderation-action.js'));
const admin=req('firebase-admin');
admin.initializeApp({projectId:'demo-ccs-regional'});
const db=admin.firestore();
const {banUserAction}=req('../lib/user-ban');
const context={require:req,module:{exports:{}},console,Promise,Error};
vm.runInThisContext('(function(require,module){' + fs.readFileSync(path.join(repo,'telegram_auth_server/api/moderation-action.js'),'utf8')+'\nmodule.exports.actions=handlers;})')(req,context.module);
const actions=context.module.exports.actions;
const actor=async uid=>({uid,user:(await db.doc('users/'+uid).get()).data()});
async function setup(){
  for(const [uid,data] of Object.entries({
    banMod:{role:'moderator',country:'Latvia',moderatorCountryCodes:['EE']},
    banEmpty:{role:'moderator',country:'Estonia',moderatorCountryCodes:[],globalModerator:true},
    banAdmin:{role:'admin',country:'Latvia'},banAdminOther:{role:'admin',country:'Germany'},
    banTarget:{role:'user',country:'Estonia',deviceIds:['test-device-123']},
    banForeign:{role:'user',country:'Latvia'},banUnknown:{role:'user',country:'',countryCode:'EE'},
  })) await db.doc('users/'+uid).set({uid,username:uid,deleted:false,banned:false,verified:false,...data});
  const logs=await db.collection('moderation_logs').where('action','==','user_banned').get();
  for(const doc of logs.docs) await doc.ref.delete();
  const notices=await db.collection('admin_notifications').where('type','==','moderator_user_banned').get();
  for(const doc of notices.docs) await doc.ref.delete();
}
test.before(setup);
test.after(async()=>{await db.terminate();await admin.app().delete();});
test('cross-country, missing-assignment and missing-profile bans fail with no notices',async()=>{
  for(const [uid,target] of [['banMod','banForeign'],['banEmpty','banTarget'],['banMod','banUnknown']]) {
    await assert.rejects(banUserAction({actor:await actor(uid),body:{targetUserId:target,days:3,reason:'test',requestId:'denied-'+target}}));
    assert.equal((await db.doc('users/'+target).get()).data().banned,false);
  }
  assert.equal((await db.collection('admin_notifications').where('type','==','moderator_user_banned').get()).size,0);
});
test('successful regional ban atomically records all-admin alerts and device ban, once on retry',async()=>{
  const args={actor:await actor('banMod'),body:{targetUserId:'banTarget',days:7,reason:'Repeated abuse',requestId:'success-1'}};
  const result=await banUserAction(args);
  assert.equal(result.alreadyApplied,false);
  assert.equal((await banUserAction(args)).alreadyApplied,true);
  const user=(await db.doc('users/banTarget').get()).data();
  assert.equal(user.banned,true);
  assert.equal(user.bannedByUid,'banMod');
  assert.equal((await db.doc('device_bans/test-device-123').get()).data().banned,true);
  const admins=await db.collection('users').where('role','==','admin').get();
  const notices=await db.collection('admin_notifications').where('type','==','moderator_user_banned').get();
  assert.equal(notices.size,admins.docs.filter(d=>!d.data().banned&&!d.data().deleted).length);
  assert(notices.docs.every(d=>d.data().countryCode==='EE'&&d.data().reason==='Repeated abuse'&&d.data().actorUserId==='banMod'));
  const users=new Set(notices.docs.map(d=>d.data().userId));
  assert(users.has('banAdmin'));assert(users.has('banAdminOther'));
  assert(!users.has('banEmpty'));
});
test('backend re-reads moderator assignments instead of trusting stale actor data',async()=>{
  const stale=await actor('banMod');
  await db.doc('users/banMod').update({moderatorCountryCodes:[]});
  await assert.rejects(banUserAction({actor:stale,body:{targetUserId:'banTarget',days:3,reason:'test',requestId:'stale'}}));
  await db.doc('users/banMod').update({moderatorCountryCodes:['EE']});
});
test('admins can ban across countries and do not generate moderator-ban alerts',async()=>{
  const before=(await db.collection('admin_notifications').get()).size;
  await banUserAction({actor:await actor('banAdminOther'),body:{targetUserId:'banForeign',days:2,reason:'test',requestId:'admin-1'}});
  assert.equal((await db.doc('users/banForeign').get()).data().banned,true);
  assert.equal((await db.collection('admin_notifications').get()).size,before);
});
for(const [action,collection,body] of [
  ['delete_global_message','global_chat',{messageId:'apiLV'}],
  ['set_forum_topic_pinned','forum_topics',{topicId:'apiLV',pinned:true}],
  ['update_forum_topic_header','forum_topics',{topicId:'apiLV',description:'changed'}],
  ['delete_forum_topic','forum_topics',{topicId:'apiLV'}],
  ['delete_forum_reply','forum_topics',{topicId:'apiLV',replyId:'reply'}],
]) test(`backend ${action} rejects foreign records despite spoofed payload country`,async()=>{
  await db.doc(collection+'/apiLV').set({countryCode:'LV',authorId:'other',userId:'other'});
  if(action==='delete_forum_reply') await db.doc('forum_topics/apiLV/replies/reply').set({userId:'other'});
  await assert.rejects(actions[action]({actor:await actor('banMod'),body:{...body,countryCode:'EE'}}));
  assert.equal((await db.doc(collection+'/apiLV').get()).exists,true);
});
test('global clear only touches the chosen assigned country',async()=>{
  for(const code of ['EE','LV']) await db.doc('global_chat/clear'+code).set({countryCode:code,timestamp:admin.firestore.Timestamp.now()});
  await assert.rejects(actions.clear_global_chat({actor:await actor('banMod'),body:{countryCode:'LV'}}));
  await actions.clear_global_chat({actor:await actor('banMod'),body:{countryCode:'EE'}});
  assert.equal((await db.doc('global_chat/clearEE').get()).exists,false);
  assert.equal((await db.doc('global_chat/clearLV').get()).exists,true);
});
