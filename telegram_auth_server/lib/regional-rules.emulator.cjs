const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8189';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
const project = 'demo-ccs-regional';
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
test.before(async()=>{
  const rulesPath=require('node:path').resolve(__dirname, '../../firestore.rules');
  const rules=await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`,{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({rules:{files:[{name:'firestore.rules',content:fs.readFileSync(rulesPath,'utf8')}]}})});
  assert.equal(rules.status,200,await rules.text());
  for(const [uid,user] of Object.entries({
    admin:{role:'admin',country:'Latvia'},
    ee:{role:'moderator',country:'Latvia',moderatorCountryCodes:['EE']},
    lv:{role:'moderator',country:'Estonia',moderatorCountryCodes:['LV']},
    empty:{role:'moderator',country:'Estonia',moderatorCountryCodes:[],globalModerator:true},
    flagged:{role:'user',globalModerator:true,moderatorCountryCodes:['EE']},
    targetEE:{role:'user',country:'Estonia'},targetLV:{role:'user',country:'Latvia'},
  })) await seed('users/'+uid,{uid,verified:false,deleted:false,banned:false,...user});
});

for(const [uid,code,allowed] of [['ee','EE',true],['ee','LV',false],['lv','EE',false],['empty','EE',false],['flagged','EE',true],['flagged','LV',false],['admin','EE',true],['admin','LV',true]]) {
  test(`${uid}: global message deletion in ${code} ${allowed?'allowed':'denied'}`,async()=>{
    const id=`global_${uid}_${code}`;
    await seed('global_chat/'+id,{countryCode:code,userId:'someone',text:'hi'});
    const res=await request('global_chat/'+id,uid,'DELETE');
    assert.equal(res.status,allowed?200:403,await res.text());
  });
  test(`${uid}: topic pinning in ${code} ${allowed?'allowed':'denied'}`,async()=>{
    const id=`topic_${uid}_${code}`;
    await seed('forum_topics/'+id,{countryCode:code,authorId:'someone',status:'pending',isPinned:false});
    const res=await request('forum_topics/'+id,uid,'PATCH',{isPinned:true});
    assert.equal(res.status,allowed?200:403,await res.text());
  });
  test(`${uid}: reply deletion uses parent topic ${code}`,async()=>{
    const id=`reply_${uid}_${code}`;
    await seed('forum_topics/'+id,{countryCode:code,authorId:'someone'});
    await seed('forum_topics/'+id+'/replies/r',{countryCode:'EE',userId:'someone'});
    const res=await request('forum_topics/'+id+'/replies/r',uid,'DELETE');
    assert.equal(res.status,allowed?200:403,await res.text());
  });
}
test('moderators cannot set a ban directly, even in their assigned country',async()=>{
  for(const target of ['targetEE','targetLV']) {
    const res=await request('users/'+target,'ee','PATCH',{banned:true});
    assert.equal(res.status,403,await res.text());
  }
});
test('admins can ban users in any profile country directly',async()=>{
  for(const target of ['targetEE','targetLV']) {
    const res=await request('users/'+target,'admin','PATCH',{banned:true});
    assert.equal(res.status,200,await res.text());
  }
});
test('moderator unban is limited to assigned profile country',async()=>{
  let res=await request('users/targetEE','ee','PATCH',{banned:false});
  assert.equal(res.status,200,await res.text());
  res=await request('users/targetLV','ee','PATCH',{banned:false});
  assert.equal(res.status,403,await res.text());
});
test('moderator cannot expand their own country assignments',async()=>{
  const res=await request('users/ee','ee','PATCH',{moderatorCountryCodes:['EE','LV']});
  assert.equal(res.status,403,await res.text());
});
test('group monitoring is scoped to the stored group country',async()=>{
  for(const code of ['EE','LV']) {
    await seed('chats/group'+code,{countryCode:code,isGroup:true,memberIds:['targetEE','targetLV']});
    const res=await request('chats/group'+code,'ee');
    assert.equal(res.status,code==='EE'?200:403,await res.text());
  }
});

test('regional report queries allow assigned country and deny a global moderator query',async()=>{
  await seed('user_reports/queryEE',{countryCode:'EE',reportedUid:'targetEE'});
  await seed('user_reports/queryLV',{countryCode:'LV',reportedUid:'targetLV'});
  const query=async filter=>fetch(base+':runQuery',{method:'POST',headers:{authorization:'Bearer '+token('ee'),'content-type':'application/json'},body:JSON.stringify({structuredQuery:{from:[{collectionId:'user_reports'}],...(filter?{where:{fieldFilter:{field:{fieldPath:'countryCode'},op:'EQUAL',value:{stringValue:filter}}}}:{})}})});
  const scoped=await query('EE');assert.equal(scoped.status,200,await scoped.text());
  const foreign=await query('LV');assert.equal(foreign.status,403,await foreign.text());
  const global=await query();assert.equal(global.status,403,await global.text());
});
test('moderator-owned foreign topic does not grant moderation over other replies',async()=>{
  await seed('forum_topics/modOwned',{authorId:'ee',countryCode:'LV'});
  await seed('forum_topics/modOwned/replies/r',{userId:'someone'});
  const res=await request('forum_topics/modOwned/replies/r','ee','DELETE');
  assert.equal(res.status,403,await res.text());
});
test('legacy community records are LV-only; invalid country never grants access',async()=>{
  for(const [id,data,uid,allowed] of [
    ['legacyEE',{userId:'someone'},'ee',false],
    ['legacyLV',{userId:'someone'},'lv',true],
    ['invalidLV',{userId:'someone',countryCode:''},'lv',false],
  ]) {
    await seed('global_chat/'+id,data);
    const res=await request('global_chat/'+id,uid,'DELETE');
    assert.equal(res.status,allowed?200:403,await res.text());
  }
});

test('spot creation requires a listed country and respects region bans for every role', async()=>{
  await seed('app_config/main',{bannedCountryCodes:['RU'],bannedCountryKeys:['ru']});
  for(const uid of ['admin','ee','empty']) {
    for(const [code,allowed] of [['EE',true],['LV',true],['RU',false],['EG',false],['ZZ',false],['',false],[null,false]]) {
      const data={addedByUid:uid,name:'Test spot',cityCountry:'Test',categories:['Photo'],status:'pending'};
      if(code!==null) data.countryCode=code;
      const res=await request(`spots/region_${uid}_${code===null?'missing':code||'empty'}`,uid,'PATCH',data);
      assert.equal(res.status,allowed?200:403,`${uid}/${code}: ${await res.text()}`);
    }
  }
  await seed('app_config/main',{bannedCountryCodes:[],bannedCountryKeys:['ee']});
  const res=await request('spots/region_legacy_ban','admin','PATCH',{addedByUid:'admin',name:'Test',cityCountry:'Test',categories:['Photo'],status:'pending',countryCode:'EE'});
  assert.equal(res.status,403,await res.text());
  await seed('app_config/main',{bannedCountryCodes:[],bannedCountryKeys:[]});
});

test('forum photo galleries allow old topics and up to four HTTPS photos', async()=>{
  for(const [label,photos,allowed] of [
    ['legacy',undefined,true],['empty',[],true],['one',['https://example.com/1.jpg'],true],
    ['four',Array.from({length:4},(_,i)=>`https://example.com/${i}.jpg`),true],
    ['five',Array(5).fill('https://example.com/p.jpg'),false],
    ['type','https://example.com/p.jpg',false],['item',[42],false],['local',['file:///private'],false],
  ]) {
    const data={authorId:'ee',title:'Photos',category:'General',categoryId:'general',description:'Test',avatarUrl:'',authorName:'ee',countryCode:'EE',authorCountryCode:'LV',country:'Latvia',repliesCount:0,isPinned:false,status:'pending',rejectionReason:null,reviewedBy:null,reviewedAt:null};
    if(photos!==undefined) data.photoUrls=photos;
    const res=await fetch(base+':commit',{method:'POST',headers:{authorization:'Bearer '+token('ee'),'content-type':'application/json'},body:JSON.stringify({writes:[{update:{name:`projects/${project}/databases/(default)/documents/forum_topics/photos_${label}`,fields:fields(data)},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'lastReplyAt',setToServerValue:'REQUEST_TIME'}]}]})});
    assert.equal(res.status,allowed?200:403,`${label}: ${await res.text()}`);
  }
});

test('group spots and forum enforce membership and exclude public queries', async()=>{
  for(const uid of ['memberA','memberB','outsider']) await seed('users/'+uid,{uid,role:'user',country:'Latvia',banned:false,deleted:false,verified:false});
  await seed('chats/eventA',{isGroup:true,isPrivate:true,memberIds:['memberA'],name:'A'});
  await seed('chats/eventB',{isGroup:true,isPrivate:false,memberIds:['memberB'],name:'B'});
  const spot={visibility:'group',sharedGroupIds:['eventA','eventB'],sharedGroups:[],isTemporary:true,verifiedOnly:false,status:'approved',addedByUid:'memberA',countryCode:'LV',name:'Private event'};
  await seed('spots/groupEvent',spot);
  await seed('forum_topics/groupEvent',{...spot,authorId:'memberA'});
  await seed('forum_topics/groupEvent/replies/r',{userId:'memberA',text:'Private reply'});
  await seed('spot_reviews/groupComment',{spotId:'groupEvent',userId:'memberA',comment:'Private comment'});
  await seed('chats/eventA/spot_links/groupEvent',{spotId:'groupEvent'});
  for(const uid of ['memberA','memberB','outsider','admin','ee']) {
    const allowed=['memberA','memberB','admin'].includes(uid);
    for(const path of ['spots/groupEvent','forum_topics/groupEvent','forum_topics/groupEvent/replies/r','spot_reviews/groupComment']) {
      const res=await request(path,uid);assert.equal(res.status,allowed?200:403,`${uid} ${path}: ${await res.text()}`);
    }
  }
  await seed('chats/eventB',{memberIds:[]});
  let res=await request('spots/groupEvent','memberB'); assert.equal(res.status,403,await res.text());
  res=await request('forum_topics/groupEvent/replies/r','memberB');assert.equal(res.status,403,await res.text());
  await seed('chats/eventB',{memberIds:['outsider']});
  res=await request('spots/groupEvent','outsider');assert.equal(res.status,200,await res.text());
  res=await request('chats/eventA/spot_links/groupEvent','outsider');assert.equal(res.status,403,await res.text());
  res=await request('spots/groupEvent','memberA','PATCH',{visibility:'public',sharedGroupIds:[]});assert.equal(res.status,403,await res.text());
  await seed('spots/publicEvent',{...spot,visibility:'public',sharedGroupIds:[]});
  const query=await fetch(base+':runQuery',{method:'POST',headers:{authorization:'Bearer '+token('memberB'),'content-type':'application/json'},body:JSON.stringify({structuredQuery:{from:[{collectionId:'spots'}],where:{compositeFilter:{op:'AND',filters:[['status','approved'],['visibility','public'],['verifiedOnly',false]].map(([field,v])=>({fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:value(v)}}))}}}})});
  assert.equal(query.status,200,await query.text());
});

test('group creation rejects nonmembers and creates spot/forum together', async()=>{
  const uid='groupCreator';await seed('users/'+uid,{uid,role:'user',country:'Latvia',banned:false,deleted:false,verified:false});
  await seed('chats/creatorGroup',{isGroup:true,memberIds:[uid]});
  await seed('chats/foreignGroup',{isGroup:true,memberIds:['someoneElse']});
  const spot={addedByUid:uid,addedBy:'Creator',name:'Group event',cityCountry:'Riga, Latvia',countryCode:'LV',categories:['Meet'],status:'pending',isTemporary:true,verifiedOnly:false,visibility:'group',sharedGroupIds:['creatorGroup'],sharedGroups:[],photoUrl:'https://example.com/photo.jpg'};
  let res=await request('spots/forgedGroup',uid,'PATCH',{...spot,sharedGroupIds:['foreignGroup']});assert.equal(res.status,403,await res.text());
  res=await request('spots/notTemporary',uid,'PATCH',{...spot,isTemporary:false});assert.equal(res.status,403,await res.text());
  const spotId='atomicGroup'+Date.now();
  const allGroups=Array.from({length:8},(_,i)=>'maxGroup'+i);
  for(const id of allGroups) await seed('chats/'+id,{isGroup:true,memberIds:[uid]});
  let maxResult=await request('spots/maxGroups'+Date.now(),uid,'PATCH',{...spot,sharedGroupIds:allGroups});
  assert.equal(maxResult.status,200,await maxResult.text());
  const starts={timestampValue:new Date(Date.now()+3600000).toISOString()},ends={timestampValue:new Date(Date.now()+7200000).toISOString()};
  const topic={title:spot.name,countryCode:'LV',authorCountryCode:'LV',country:'Latvia',category:'Meets',categoryId:'meets_events',description:'Group event',avatarUrl:spot.photoUrl,authorId:uid,authorName:'Creator',repliesCount:0,isPinned:false,status:'pending',rejectionReason:null,reviewedBy:null,reviewedAt:null,visibility:'group',sharedGroupIds:['creatorGroup'],sharedGroups:[],source:'temporary_spot',isSpotTopic:true,spotId,temporarySpotId:spotId};
  const docPath=path=>`projects/${project}/databases/(default)/documents/${path}`;
  const writes=[{update:{name:docPath('spots/'+spotId),fields:{...fields(spot),startsAt:starts,expiresAt:ends}}},
    {update:{name:docPath('chats/creatorGroup/spot_links/'+spotId),fields:fields({spotId,authorUid:uid,published:false})}},
    {update:{name:docPath('forum_topics/temporary_spot_'+spotId),fields:{...fields(topic),temporarySpotStartsAt:starts,temporarySpotExpiresAt:ends,autoExpiresAt:ends}},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'lastReplyAt',setToServerValue:'REQUEST_TIME'}]}];
  res=await fetch(base+':commit',{method:'POST',headers:{authorization:'Bearer '+token(uid),'content-type':'application/json'},body:JSON.stringify({writes})});
  assert.equal(res.status,200,await res.text());
  const eightId=spotId+'eight';
  const eightTopic={...topic,spotId:eightId,temporarySpotId:eightId,sharedGroupIds:allGroups};
  const eightWrites=[{update:{name:docPath('spots/'+eightId),fields:{...fields({...spot,sharedGroupIds:allGroups}),startsAt:starts,expiresAt:ends}}},
    ...allGroups.map(groupId=>({update:{name:docPath(`chats/${groupId}/spot_links/${eightId}`),fields:fields({spotId:eightId,authorUid:uid,published:false})}})),
    {update:{name:docPath('forum_topics/temporary_spot_'+eightId),fields:{...fields(eightTopic),temporarySpotStartsAt:starts,temporarySpotExpiresAt:ends,autoExpiresAt:ends}},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'lastReplyAt',setToServerValue:'REQUEST_TIME'}]}];
  res=await fetch(base+':commit',{method:'POST',headers:{authorization:'Bearer '+token(uid),'content-type':'application/json'},body:JSON.stringify({writes:eightWrites})});
  assert.equal(res.status,200,await res.text());
});

test('forum review decisions and country locks cannot be bypassed by clients', async()=>{
  await seed('forum_topics/locked_review', {countryCode:'EE',authorId:'someone',status:'pending',isPinned:false});
  for(const uid of ['admin','ee','flagged']) {
    const decision=await request('forum_topics/locked_review',uid,'PATCH',{status:'approved'});
    assert.equal(decision.status,403,await decision.text());
    const lock=await request('forum_review_locks/EE',uid,'PATCH',{reviewerUid:uid});
    assert.equal(lock.status,403,await lock.text());
  }
});
test('automatic topic status can only follow the canonical spot decision', async()=>{
  await seed('spots/forum_auto_guard', {countryCode:'EE',status:'pending',visibility:'public'});
  await seed('forum_topics/forum_auto_guard', {countryCode:'EE',authorId:'someone',source:'temporary_spot',spotId:'forum_auto_guard',status:'pending',isPinned:false});
  const denied=await request('forum_topics/forum_auto_guard','ee','PATCH',{status:'approved'});
  assert.equal(denied.status,403,await denied.text());
  await seed('spots/forum_auto_guard',{status:'approved'});
  const allowed=await request('forum_topics/forum_auto_guard','ee','PATCH',{status:'approved'});
  assert.equal(allowed.status,200,await allowed.text());
});
