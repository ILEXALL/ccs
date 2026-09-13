const test=require('node:test'), assert=require('node:assert/strict');
const host=process.env.FIRESTORE_EMULATOR_HOST||'127.0.0.1:8189';
if(!/^(localhost|127\.0\.0\.1):\d+$/.test(host))throw Error('Local emulator required');
process.env.FIRESTORE_EMULATOR_HOST=host;
const admin=require('firebase-admin');admin.initializeApp({projectId:'demo-forum-overlap'});
const db=admin.firestore();const {forumReviewAction:action}=require('./forum-review');
const call=(uid,operation,extra={})=>action({actor:{uid},body:{operation,sessionId:'review_session_'+uid,...extra}});
const topic=(id,code,extra={})=>db.doc('forum_topics/'+id).set({countryCode:code,status:'pending',title:id,authorId:'user',...extra});
test.beforeEach(async()=>{
 await db.doc('forum_review_locks/sessions').delete();
 for(const doc of (await db.collection('forum_publications').get()).docs)await doc.ref.delete();
 for(const doc of (await db.collection('forum_topics').get()).docs)await doc.ref.delete();
 for(const [uid,role,countries]of [['a','admin',[]],['b','admin',[]],['ee','moderator',['EE']],['ee2','moderator',['EE']],['lv','moderator',['LV']],['both','moderator',['EE','LV']],['user','user',['EE']]])
   await db.doc('users/'+uid).set({role,moderatorCountryCodes:countries,username:uid});
});
test.after(async()=>{await db.terminate();await admin.app().delete();});
test('simultaneous shared reviewers have one winner; blocker name is returned',async()=>{
 await topic('estonia','EE');
 const results=await Promise.all([call('ee','acquire'),call('ee2','acquire')]);
 assert.equal(results.filter(x=>x.acquired).length,1);
 assert.equal(results.find(x=>x.blocked).reviewerUsername,results[0].acquired?'ee':'ee2');
});
test('different pending lists coexist; admin overlaps both and is blocked',async()=>{
 await topic('estonia','EE');await topic('latvia','LV');
 assert.equal((await call('ee','acquire')).acquired,true);
 assert.equal((await call('lv','acquire')).acquired,true);
 assert.equal((await call('a','acquire')).blocked,true);
 assert.deepEqual((await call('ee','renew')).topics.map(t=>t.id),['estonia']);
});
test('shared assignments without shared pending topics do not block entry',async()=>{
 await topic('latvia','LV');
 assert.equal((await call('both','acquire')).acquired,true);
 assert.equal((await call('ee','acquire')).acquired,true);
 assert.equal((await call('ee2','acquire')).acquired,true);
 await topic('estonia','EE');
 const result=await call('ee','renew');
 assert.equal(result.blocked,true);assert.equal(result.reviewerUsername,'both');
 assert.equal((await call('ee2','decide',{topicId:'estonia',status:'approved'})).blocked,true);
});
test('admins follow overlap rule, including newly arriving topics',async()=>{
 assert.equal((await call('a','acquire')).acquired,true);
 assert.equal((await call('b','acquire')).acquired,true);
 await topic('new','EE');
 await call('a','renew');
 const result=await call('b','decide',{topicId:'new',status:'approved'});
 assert.equal(result.blocked,true);assert.equal(result.reviewerUsername,'a');
 assert.equal((await db.doc('forum_topics/new').get()).data().status,'pending');
});
test('same-account devices conflict; release and expiry restore access safely',async()=>{
 await topic('new','EE');await call('ee','acquire');
 assert.equal((await call('ee','acquire',{sessionId:'different_device_session'})).blocked,true);
 await call('ee','release');assert.equal((await call('ee2','acquire')).acquired,true);
 const ref=db.doc('forum_review_locks/sessions');const d=(await ref.get()).data();
 d.sessions.forEach(s=>s.expiresAtMillis=0);await ref.set(d);
 assert.equal((await call('ee','acquire')).acquired,true);
 assert.equal((await call('ee2','release')).released,false);
});
test('current assignments and pending status guard decisions; retries are idempotent',async()=>{
 await topic('new','EE');await topic('foreign','LV');await call('ee','acquire');
 await assert.rejects(call('user','acquire'));
 await assert.rejects(call('ee','decide',{topicId:'foreign',status:'approved'}));
 await db.doc('users/ee').update({moderatorCountryCodes:[]});
 await assert.rejects(call('ee','decide',{topicId:'new',status:'approved'}));
 await db.doc('users/ee').update({moderatorCountryCodes:['EE']});
 assert.equal((await call('ee','decide',{topicId:'new',status:'approved'})).alreadyDecided,false);
 assert.equal((await call('ee','decide',{topicId:'new',status:'approved'})).alreadyDecided,true);
 await assert.rejects(call('ee','decide',{topicId:'new',status:'rejected',rejectionReason:'changed'}));
 assert.equal((await db.doc('user_notifications/forum_reviewed_new').get()).data().userId,'user');
});
test('event topics are excluded and old country-mode clients must update',async()=>{
 await topic('event','EE',{source:'temporary_spot'});
 assert.deepEqual((await call('ee','acquire')).topics,[]);
 assert.equal((await call('ee2','acquire')).acquired,true);
 await assert.rejects(call('ee','decide',{topicId:'event',status:'approved'}));
 await assert.rejects(call('ee','acquire',{countryCode:'EE'}));
});

test('committed approval queues publication even when renewal fails; retry clears the job',async()=>{
 await topic('publish','EE',{visibility:'public'});
 await call('ee','acquire');
 await call('ee','decide',{topicId:'publish',status:'approved'});
 await db.doc('forum_review_locks/sessions').delete();
 await assert.rejects(call('ee','renew'));
 const job=db.doc('forum_publications/publish');
 assert.equal((await job.get()).exists,true);
 const {drainForumPublications}=require('./forum-publications');
 let attempts=0;
 await drainForumPublications(async()=>{attempts++;throw Error('offline');});
 assert.equal((await job.get()).exists,true);
 await drainForumPublications(async(uid,payload)=>{attempts++;assert.equal(uid,'user');assert.equal(payload.topicId,'publish');});
 assert.equal((await job.get()).exists,false);
 await drainForumPublications(async()=>{attempts++;});
 assert.equal(attempts,2);
});
test('rejection never queues a publication',async()=>{
 await topic('reject','EE');await call('ee','acquire');
 await call('ee','decide',{topicId:'reject',status:'rejected',rejectionReason:'Duplicate'});
 assert.equal((await db.doc('forum_publications/reject').get()).exists,false);
});
test('the production push module can be imported from the moderation backend',async()=>{
 const push=await import('../api/push-notification.js');
 assert.equal(typeof push.handleForumTopicCreated,'function');
 // No push tokens are seeded, so this verifies wiring using the emulator only.
 await topic('dispatch','EE',{status:'approved',visibility:'public'});
 const results=await push.handleForumTopicCreated('user',{topicId:'dispatch'});
 assert.ok(Array.isArray(results));
});

test('concurrent retry cannot discard another dispatch that later fails',async()=>{
 await topic('concurrent','EE',{status:'approved',visibility:'public'});
 const job=db.doc('forum_publications/concurrent');await job.set({topicId:'concurrent'});
 const {drainForumPublications}=require('./forum-publications');
 let entered, rejectDispatch;
 const started=new Promise(resolve=>{entered=resolve;});
 const first=drainForumPublications(async()=>{entered();await new Promise((_,reject)=>{rejectDispatch=reject;});});
 await started;
 let secondCalls=0;
 await drainForumPublications(async()=>{secondCalls++;});
 assert.equal(secondCalls,0);assert.equal((await job.get()).exists,true);
 rejectDispatch(Error('first request lost connection'));await first;
 assert.equal((await job.get()).exists,true);
 await drainForumPublications(async()=>{secondCalls++;});
 assert.equal(secondCalls,1);assert.equal((await job.get()).exists,false);
});
