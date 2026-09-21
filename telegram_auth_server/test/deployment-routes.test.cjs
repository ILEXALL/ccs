const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {fixture} = require('./support');

test('server fits the Hobby function limit and visit URL uses the shared handler', () => {
  const api = fs.readdirSync(path.join(__dirname, '../api')).filter(name => name.endsWith('.js'));
  assert.ok(api.length <= 12, `Found ${api.length} API functions`);
  assert.ok(!api.includes('spot-visit.js'));
  const config = JSON.parse(fs.readFileSync(path.join(__dirname, '../vercel.json'), 'utf8'));
  assert.equal(config.rewrites.find(r => r.source === '/api/spot-visit').destination, '/api/community?endpoint=spot-visit');
});
for (const endpoint of ['xp-sync', 'spot-visit']) {
  test(`${endpoint} exposes deployment version without weakening authentication`, async () => {
    const handler = fixture().load('../api/community.js');
    const headers = {};
    const res = {setHeader: (name,value) => {headers[name] = value;}, status(code) {this.code=code;return this;}, json(body) {this.body=body;return this;}};
    await handler({method:'POST',query:{endpoint},headers:{},body:{action:'rewards'}}, res);
    assert.equal(res.code,401);
    assert.equal(headers['X-CCS-Rewards-Version'],'weekly-live-v1');
  });
}
