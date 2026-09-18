const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8189';
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
const project = 'demo-ccs-presence';
const database = `projects/${project}/databases/(default)`;
const base = `http://${host}/v1/${database}/documents`;
const token = uid => `${Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url')}.${Buffer.from(JSON.stringify({sub:uid,user_id:uid,aud:project,iss:`https://securetoken.google.com/${project}`,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,firebase:{sign_in_provider:'custom'}})).toString('base64url')}.`;
const headers = uid => ({authorization: `Bearer ${uid === 'owner' ? 'owner' : token(uid)}`, 'content-type':'application/json'});
async function seed(path, fields) {
  const r = await fetch(`${base}/${path}`, {method:'PATCH',headers:headers('owner'),body:JSON.stringify({fields})});
  assert.equal(r.status,200,await r.text());
}
async function heartbeat(actor, subject, extra = {}) {
  return fetch(`${base}:commit`, {method:'POST',headers:headers(actor),body:JSON.stringify({writes:[{
    update:{name:`${database}/documents/user_presence/${subject}`,fields:{isOnline:{booleanValue:true},...extra}},
    updateMask:{fieldPaths:['isOnline',...Object.keys(extra)]},
    updateTransforms:['lastSeenAt','updatedAt'].map(fieldPath=>({fieldPath,setToServerValue:'REQUEST_TIME'})),
  }]})});
}
test.before(async()=>{
  const rules=fs.readFileSync(require('node:path').resolve(__dirname,'../../firestore.rules'),'utf8');
  const r=await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`,{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({rules:{files:[{name:'firestore.rules',content:rules}]}})});
  assert.equal(r.status,200,await r.text());
  for(const uid of ['expired','other','new','banned']) await seed(`users/${uid}`,{role:{stringValue:'user'},country:{stringValue:'Latvia'},banned:{booleanValue:uid==='banned'}});
  for(const uid of ['expired','banned']) await seed(`user_presence/${uid}`,{
    isOnline:{booleanValue:false},lastSeenAt:{timestampValue:'2020-01-01T00:00:00Z'},updatedAt:{timestampValue:'2020-01-01T00:00:00Z'},
    isSharingLiveLocation:{booleanValue:true},liveLocationExpiresAt:{timestampValue:'2020-01-01T00:00:00Z'},
    liveLocationVisibleToUserIds:{arrayValue:{values:[{stringValue:uid}]}},
  });
});
test('expired live sharing does not block an owner heartbeat',async()=>{
  const r=await heartbeat('expired','expired'); assert.equal(r.status,200,await r.text());
});
test('another account cannot write presence',async()=>{
  const r=await heartbeat('other','expired'); assert.equal(r.status,403,await r.text());
});
test('banned account cannot write presence',async()=>{
  const r=await heartbeat('banned','banned'); assert.equal(r.status,403,await r.text());
});
test('heartbeat exemption cannot add coordinates or alter the audience',async()=>{
  for(const extra of [{lat:{doubleValue:56.9}},{liveLocationVisibleToUserIds:{arrayValue:{values:[{stringValue:'other'}]}}}]) {
    const r=await heartbeat('expired','expired',extra); assert.equal(r.status,403,await r.text());
  }
});
test('new owner can create valid presence',async()=>{
  const r=await heartbeat('new','new'); assert.equal(r.status,200,await r.text());
});
