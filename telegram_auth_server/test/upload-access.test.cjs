const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const uploadAccess = require('../lib/upload-access');

function fixture(rows = {}) {
  let signed = 0;
  const firebase = {admin:{auth:()=>({verifyIdToken:async(token, revoked)=>{
    assert.equal(revoked,true);
    if(token !== 'valid') throw new Error('invalid token');
    return {uid:'owner'};
  }})},db:{collection:name=>({doc:id=>({get:async()=>({exists:!!rows[`${name}/${id}`],data:()=>rows[`${name}/${id}`]})})})}};
  const context=vm.createContext({firebase,uploadAccess,process:{env:{R2_PUBLIC_BASE_URL:'https://images.example.invalid'}},
    S3Client:class {},PutObjectCommand:class {constructor(input){this.input=input;}},
    getSignedUrl:async()=>{signed++;return 'synthetic-upload-url';}});
  const source=fs.readFileSync(path.join(__dirname,'../api/r2-presign-upload.js'),'utf8')
    .replace(/^import .*;\r?\n/gm,'').replace('export default ','');
  vm.runInContext(source,context);
  return {signed:()=>signed,request:async(headers,body={path:'users/owner/avatar.jpg',contentType:'image/jpeg'})=>{
    const res={status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
    await context.handler({method:'POST',headers,body},res);return res;
  }};
}
test('upload endpoint never issues a capability to anonymous or invalid sessions',async()=>{
  const f=fixture();
  for(const headers of [{},{authorization:'Bearer invalid'}]) assert.equal((await f.request(headers)).code,401);
  assert.equal(f.signed(),0);
});
test('upload endpoint rejects path takeover and deleting/banned users before signing',async()=>{
  for(const rows of [{'account_deletions/owner':{status:'queued'}},{'users/owner':{banned:true}}]){
    const f=fixture(rows);assert.equal((await f.request({authorization:'Bearer valid'})).code,403);assert.equal(f.signed(),0);
  }
  const f=fixture();
  for(const path of ['users/other/avatar.jpg','spots/missing/photo.jpg']) assert.equal((await f.request({authorization:'Bearer valid'},{path,contentType:'image/jpeg'})).code,403);
  assert.equal(f.signed(),0);
});
test('authenticated owner can upload supported images; malformed paths and types fail closed',async()=>{
  const f=fixture();const headers={authorization:'Bearer valid'};
  assert.equal((await f.request(headers)).code,200);
  assert.equal((await f.request(headers,{path:'users/owner/../other.jpg',contentType:'image/jpeg'})).code,400);
  assert.equal((await f.request(headers,{path:'users/owner/file.exe',contentType:'application/octet-stream'})).code,400);
  assert.equal(f.signed(),1);
});
