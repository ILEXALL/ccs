const test = require('node:test');
const assert = require('node:assert/strict');
const { evaluateProfileXp, evaluateFirstCarXp } = require('../lib/xp/profile-garage-xp');
const { evaluatePermanentSpotApprovalXp } = require('../lib/xp/spot-xp');

function rewards(awards) {
  const result = Object.fromEntries(awards.map(({ action, amount }) => [action, amount]));
  assert.equal(Object.keys(result).length, awards.length, 'duplicate reward action');
  return result;
}

test('oracle: 16 profile condition combinations', () => {
  for (let mask = 0; mask < 16; mask++) {
    const expected = {};
    if (mask & 1) expected['profile.avatar'] = 50;
    if (mask & 2) expected['profile.bio'] = 40;
    if (mask & 4) expected['profile.city'] = 30;
    if (mask & 8) expected['profile.social'] = 30;
    if (mask === 15) expected['profile.full'] = 100;
    assert.deepEqual(rewards(evaluateProfileXp('synthetic', {
      photoUrl: mask & 1 ? 'avatar' : '', bio: mask & 2 ? 'x'.repeat(20) : '',
      city: mask & 4 ? 'Riga' : '', telegram: mask & 8 ? 'account' : '',
    })), expected, `profile mask=${mask}`);
  }
});

test('oracle: 192 first-car condition combinations', () => {
  let cases = 0;
  for (const named of [false, true])
  for (const length of [0, 19, 20])
  for (const count of [0, 1, 2, 3])
  for (const build of [false, true])
  for (const tags of [false, true])
  for (const alternate of [false, true]) {
    const photos = Array.from({ length: count }, (_, i) => `photo-${i}`);
    const expected = { 'garage.first_car': 50 };
    if (count) expected['garage.first_car_photo'] = 50;
    if (length === 20) expected['garage.first_car_description'] = 50;
    if (count === 3) expected['garage.first_car_gallery'] = 25;
    if (named && length === 20 && count && build && tags) expected['garage.first_car_full'] = 75;
    const car = { name: named ? 'Car' : '', description: 'x'.repeat(length),
      photoPath: photos[0] || '', photoPaths: photos.concat(photos),
      [alternate ? 'useType' : 'buildType']: build ? 'daily' : '', tags: tags ? ['daily'] : [] };
    assert.deepEqual(rewards(evaluateFirstCarXp('synthetic', { garage: [car] })), expected,
      JSON.stringify({ named, length, count, build, tags, alternate }));
    cases++;
  }
  assert.equal(cases, 192);
});

test('oracle: 1920 spot condition combinations', () => {
  let cases = 0;
  for (const status of ['pending', 'edited', 'approved', 'rejected'])
  for (const temporary of [false, true])
  for (const author of ['addedByUid', 'ownerUid', 'missing'])
  for (const length of [0, 1, 19, 20, 21])
  for (const count of [0, 1, 2, 3])
  for (const reel of [false, true])
  for (const duplicates of [false, true]) {
    const photos = Array.from({ length: count }, (_, i) => `photo-${i}`);
    const spot = { status, isTemporary: temporary, description: `  ${'x'.repeat(length)}  `,
      photoUrl: photos[0] || '', photoUrls: duplicates ? photos.concat(photos) : photos,
      reelLink: reel ? 'https://example.invalid/reel' : '' };
    if (author !== 'missing') spot[author] = 'synthetic';
    const expected = {};
    if (status === 'approved' && !temporary && author !== 'missing') {
      expected['spot.approved'] = 50;
      if (length >= 20) expected['spot.description'] = 15;
      if (count > 0) expected['spot.photo'] = 25;
      if (count === 3 || reel) expected['spot.media_bundle'] = 10;
    }
    assert.deepEqual(rewards(evaluatePermanentSpotApprovalXp('synthetic-spot', spot)), expected,
      JSON.stringify({ status, temporary, author, length, count, reel, duplicates }));
    cases++;
  }
  assert.equal(cases, 1920);
});
