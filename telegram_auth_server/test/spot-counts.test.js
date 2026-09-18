const test = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./support');

test('spot milestones count only approved permanent creations once, using legacy creator fallback', async () => {
  const f = fixture({'users/viewer': {}});
  f.rows.get('app_config/xp').achievements_enabled = true;
  for (let i=0;i<69;i++) f.rows.set('spots/'+i, {addedByUid:'tester',ownerUid:'tester',status:'approved',isTemporary:i>=48});
  f.rows.set('spots/legacy', {ownerUid:'tester',status:'approved'});
  f.rows.set('spots/owned-not-created', {addedByUid:'other',ownerUid:'tester',status:'approved'});
  for (const status of ['pending','rejected']) f.rows.set('spots/'+status, {addedByUid:'tester',status});
  f.rows.set('spots/deleted', {addedByUid:'tester',status:'approved',deleted:true});
  const {creatorSpotCount} = f.load('../lib/xp/public-profile.js');
  assert.equal((await creatorSpotCount('viewer','tester')).count,49);
  f.rows.set('spots/milestone', {addedByUid:'tester',status:'approved'});
  const {syncAchievements,publicAchievements} = f.load('../lib/xp/achievements.js');
  const board = await syncAchievements('tester');
  assert.ok(board.items.filter(i=>i.category==='spots').every(i=>i.progress===50 && i.status==='confirmed'));
  const before=JSON.stringify([...f.rows]);
  await syncAchievements('tester');
  assert.equal(JSON.stringify([...f.rows]),before);
  assert.equal((await publicAchievements('viewer','tester')).items[0].progress,50);
});

test('creator count respects profile privacy and blocks but permits owner of private profile', async () => {
  for (const target of [{publicProfile:false},{settings:{publicProfile:false}},{banned:true},{deleted:true},{blockedUserIds:['viewer']}]) {
    const f=fixture({'users/viewer':{},'users/tester':target});
    await assert.rejects(f.load('../lib/xp/public-profile.js').creatorSpotCount('viewer','tester'),/unavailable/);
  }
  const f=fixture({'users/viewer':{blockedUserIds:['tester']},'users/tester':{publicProfile:false}});
  const {creatorSpotCount}=f.load('../lib/xp/public-profile.js');
  await assert.rejects(creatorSpotCount('viewer','tester'),/unavailable/);
  assert.equal((await creatorSpotCount('tester','tester')).count,0);
  await assert.rejects(creatorSpotCount('tester','bad/id'),/Invalid/);
});
