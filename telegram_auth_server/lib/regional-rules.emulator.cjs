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
    const res=await request('forum_topics/'+id,uid,'PATCH',{isPinned:true,status:'approved'});
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
