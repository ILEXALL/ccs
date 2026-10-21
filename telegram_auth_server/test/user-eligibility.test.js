const {test} = require('node:test');
const assert = require('node:assert/strict');
const {eligibleForVerification, manuallyApprovedPermanentSpot} = require('../lib/user-eligibility');
const {fixture} = require('./support');
const profile = () => ({photoUrl:'https://images.example/avatar.jpg',garage:[{description:'My car',photoPath:'https://images.example/car.jpg'}]});
test('automatic verification requires server level 5, avatar and a complete car', () => {
  assert.equal(eligibleForVerification(profile(),399),false);
  assert.equal(eligibleForVerification(profile(),400),true);
  assert.equal(eligibleForVerification({...profile(),photoUrl:''},400),false);
  assert.equal(eligibleForVerification({...profile(),garage:[]},400),false);
  assert.equal(eligibleForVerification({...profile(),garage:[{description:'   ',photoPath:'https://images.example/car.jpg'}]},400),false);
  assert.equal(eligibleForVerification({...profile(),garage:[{description:'Car',photoPath:'C:/car.jpg'}]},400),false);
  assert.equal(eligibleForVerification({...profile(),garage:[{description:'Car'},{photoPath:'https://images.example/car.jpg'}]},400),false);
  assert.equal(eligibleForVerification({...profile(),garage:[{},...profile().garage]},400),true);
  for (const flag of ['banned','deleted','verified']) assert.equal(eligibleForVerification({...profile(),[flag]:true},400),false);
  assert.equal(eligibleForVerification({...profile(),verified:false,verifiedUpdatedByUid:'admin'},400),false);
});
test('trust counts only manually reviewed permanent creations belonging to the user', () => {
  const spot={addedByUid:'owner',status:'approved',reviewedByUid:'mod',reviewedAt:123};
  assert.equal(manuallyApprovedPermanentSpot(spot,'owner'),true);
  for (const patch of [{isTemporary:true},{status:'rejected'},{deleted:true},{reviewedByUid:'owner'},{reviewedByUid:''},{reviewedAt:null},{approvalMethod:'trusted_creator'},{approvalMethod:'staff_creation'},{addedByUid:'someone'}]) {
    assert.equal(manuallyApprovedPermanentSpot({...spot,...patch},'owner'),false);
  }
});
test('verification sync uses protected stats and is idempotent', async () => {
 const f=fixture({'users/tester':{...profile(),level:99,xpTotal:99999}});
 const {syncAutomaticVerification}=f.load('../lib/user-eligibility.js');
 const admin={firestore:{FieldValue:{serverTimestamp:()=>123}}};
 assert.equal(await syncAutomaticVerification(f.db,admin,'tester'),false);
 f.rows.set('xp_user_stats/tester',{xpTotal:400});
 assert.equal(await syncAutomaticVerification(f.db,admin,'tester'),true);
 assert.equal(f.rows.get('users/tester').verified,true);
 assert.equal(await syncAutomaticVerification(f.db,admin,'tester'),false);
});
test('earning level 5 grants verification in the XP transaction', async () => {
 const f=fixture({'users/tester':profile(),'xp_user_stats/tester':{xpTotal:350}});
 await f.awards.awardXp({userId:'tester',action:'profile.avatar',objectType:'profile',objectId:'tester',stage:'avatar',amount:50});
 assert.equal(f.rows.get('users/tester').verified,true);
});
