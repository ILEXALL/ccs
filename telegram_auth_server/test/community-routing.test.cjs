const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json')));
test('all legacy URLs dispatch to their original handler with request intact', async () => {
  for (const name of ['xp-sync', 'xp-leaderboard', 'spot-visit']) {
    const rewrite = config.rewrites.find(row => row.source === '/api/' + name);
    assert.ok(rewrite);
    const target = new URL(rewrite.destination, 'https://example.test');
    assert.equal(target.pathname, '/api/community');
    const req = {method:'POST', headers:{authorization:'Bearer test'}, body:{action:'sync_me'}, query:Object.fromEntries(target.searchParams)};
    const res = {};
    let called = false;
    const module = {exports:{}};
    vm.runInNewContext(fs.readFileSync(path.join(root,'api/community.js'),'utf8'), {module, require: id => (actualReq, actualRes) => {
      assert.equal(id, '../handlers/' + name);
      assert.equal(actualReq,req); assert.equal(actualRes,res); called=true;
    }});
    await module.exports(req,res);
    assert.ok(called);
  }
});
test('unknown routes do not dispatch and function count fits Hobby limit', () => {
  const module={exports:{}};
  vm.runInNewContext(fs.readFileSync(path.join(root,'api/community.js'),'utf8'),{module,require:()=>()=>assert.fail('Unexpected dispatch')});
  for (const endpoint of ['constructor','unknown',undefined,['xp-sync']]) {
    let status;
    module.exports({query:{endpoint}},{status(code){status=code; return this;},json(){}});
    assert.equal(status,404);
  }
  assert.equal(fs.readdirSync(path.join(root,'api')).filter(f=>f.endsWith('.js')).length,12);
});
