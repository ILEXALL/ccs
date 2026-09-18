const test = require('node:test');
const assert = require('node:assert/strict');
const {recordSpotVisit, rigaDay} = require('../lib/spot-visits');
const now = Date.parse('2026-09-14T12:00:00Z');
function fixture() {
  const rows = new Map([
    ['users/u', {verified: true}],
    ['spots/s', {status: 'approved', lat: 0, lng: 0}],
    ['live_locations/u', {lat: 0, lng: 0, updatedAt: now, expiresAt: now + 60000, accuracy: 10}],
  ]);
  const db = {collection: name => ({doc: id => ({key: `${name}/${id}`})}),
    runTransaction: async fn => {
      const writes = [];
      const result = await fn({get: async ref => ({exists: rows.has(ref.key), data: () => rows.get(ref.key)}),
        create: (ref, data) => { assert.ok(!rows.has(ref.key)); writes.push([ref.key, data]); }});
      for (const [key, value] of writes) rows.set(key, value);
      return result;
    }};
  return {db, rows};
}

test('nearby visit records once per Riga day, without coordinates or XP', async () => {
  const {db, rows} = fixture();
  assert.equal((await recordSpotVisit(db, 'u', 's', now)).duplicate, false);
  assert.equal((await recordSpotVisit(db, 'u', 's', now + 1000)).duplicate, true);
  const records = [...rows.entries()].filter(([key]) => key.startsWith('spot_visit_records/'));
  assert.equal(records.length, 1);
  assert.equal(records[0][1].status, 'observed');
  assert.equal(records[0][1].xpAwarded, false);
  assert.equal('lat' in records[0][1], false);
  assert.equal('coordinates' in records[0][1], false);
});

test('radius is 100m, not rounded to include 100.4m', async () => {
  for (const [meters, accepted] of [[99.6, true], [100.4, false], [150, false]]) {
    const {db, rows} = fixture();
    rows.get('live_locations/u').lat = meters / 6371000 * 180 / Math.PI;
    if (accepted) assert.equal((await recordSpotVisit(db, 'u', 's', now)).recorded, true);
    else await assert.rejects(recordSpotVisit(db, 'u', 's', now), /location/);
  }
});

test('stale, future, expired, mock and inaccurate positions cannot record visits', async () => {
  for (const change of [{updatedAt: now - 150001}, {updatedAt: now + 1}, {expiresAt: now},
    {isMocked: true}, {accuracy: 101}, {accuracy: -1}, {lat: NaN}, {lat: 91}]) {
    const {db, rows} = fixture(); Object.assign(rows.get('live_locations/u'), change);
    await assert.rejects(recordSpotVisit(db, 'u', 's', now));
  }
  const {db, rows} = fixture(); rows.delete('live_locations/u');
  await assert.rejects(recordSpotVisit(db, 'u', 's', now));
});

test('deleted, unapproved, private, expired and upcoming spots do not qualify', async () => {
  for (const change of [{deleted: true}, {status: 'pending'}, {visibility: 'group'},
    {isTemporary: true, expiresAt: now}, {isTemporary: true, expiresAt: now + 60000, startsAt: now + 1}]) {
    const {db, rows} = fixture(); Object.assign(rows.get('spots/s'), change);
    await assert.rejects(recordSpotVisit(db, 'u', 's', now), /Spot/);
  }
});

test('private user identity, bans and verified-only eligibility are enforced', async () => {
  const {db, rows} = fixture();
  rows.get('spots/s').verifiedOnly = true; rows.get('users/u').verified = false;
  await assert.rejects(recordSpotVisit(db, 'u', 's', now));
  rows.get('users/u').verified = true; rows.get('users/u').banned = true;
  await assert.rejects(recordSpotVisit(db, 'u', 's', now));
  await assert.rejects(recordSpotVisit(db, 'missing', 's', now));
  await assert.rejects(recordSpotVisit(db, 'u', '../s', now));
});

test('Riga date boundaries use the server date, including summer and winter', () => {
  assert.equal(rigaDay(Date.parse('2026-09-14T21:00:00Z')), '2026-09-15');
  assert.equal(rigaDay(Date.parse('2026-01-14T21:59:59Z')), '2026-01-14');
  assert.equal(rigaDay(Date.parse('2026-01-14T22:00:00Z')), '2026-01-15');
});

test('endpoint binds visit to authenticated UID and rejects missing or invalid tokens', async () => {
  const fs = require('node:fs'); const path = require('node:path'); const vm = require('node:vm');
  const calls = [];
  const module = {exports: {}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../handlers/spot-visit.js'), 'utf8'), {
    module,
    require: name => name.includes('firebase-admin') ? {
      db: {}, admin: {auth: () => ({verifyIdToken: async token => {
        if (token !== 'valid') throw new Error('Invalid token');
        return {uid: 'authenticated-user'};
      }})},
    } : {recordSpotVisit: async (_, uid, spotId) => {calls.push({uid, spotId}); return {recorded: true};}},
  });
  const response = () => ({code: 0, setHeader() {}, status(code) {this.code = code; return this;}, json(value) {this.value = value; return this;}});
  for (const header of ['', 'Bearer invalid']) {
    const res = response(); await module.exports({method: 'POST', headers: {authorization: header}}, res);
    assert.equal(res.code, 401);
  }
  const res = response();
  await module.exports({method: 'POST', headers: {authorization: 'Bearer valid'},
    body: {userId: 'victim', spotId: 's', lat: 80, lng: 80}}, res);
  assert.equal(res.code, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].uid, 'authenticated-user');
  assert.equal(calls[0].spotId, 's');
});
