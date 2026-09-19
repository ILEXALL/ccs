const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {fixture} = require('./support');
for (const [name, user, header, expected] of [
  ['signed out', null, undefined, 401],
  ['moderator', {role:'moderator'}, 'Bearer tester', 403],
  ['user', {role:'user'}, 'Bearer tester', 403],
  ['missing account', null, 'Bearer absent', 403],
  ['banned admin', {role:'admin',banned:true}, 'Bearer tester', 403],
  ['deleted admin', {role:'admin',deleted:true}, 'Bearer tester', 403],
  ['active admin', {role:'admin'}, 'Bearer tester', 200],
]) test('debug metrics: '+name, async () => {
  const f=fixture({'users/tester':user});
  const access=f.load('../lib/debug-access.js');
  const req={method:'GET',headers:{authorization:header}};
  assert.equal(await access.debugAccessStatus(req),expected);
  let monitoringCalls=0;
  const module={exports:{}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../api/firestore-usage.js'),'utf8'), {
    module,require: id => {
      if(id==='../lib/debug-access') return access;
      if(id==='../lib/monitoring-config') return {monitoringConfig(){monitoringCalls++;throw Error('offline monitoring sentinel');}};
      if(id==='google-auth-library')return {GoogleAuth:class {}};
      throw Error(id);
    },
  });
  const response={status(code){this.code=code;return this},json(body){this.body=body;return this}};
  await module.exports(req,response);
  assert.equal(response.code,expected===200?500:expected);
  assert.equal(monitoringCalls,expected===200?1:0);
});
test('invalid or revoked Firebase token cannot access debug',async()=>{
  const module={exports:{}};
  vm.runInNewContext(fs.readFileSync(require.resolve('../lib/debug-access.js'),'utf8'),{
    module,require:()=>({admin:{auth:()=>({verifyIdToken:async(token,checkRevoked)=>{assert.equal(checkRevoked,true);throw Error('revoked')}})},db:{collection(){throw Error('must not read database')}}}),
  });
  assert.equal(await module.exports.debugAccessStatus({headers:{authorization:'Bearer invalid'}}),401);
});
