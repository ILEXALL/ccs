const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the actual endpoint orchestration without credentials or real pushes.
function fixture(overrides = {}) {
  const spot = { addedByUid: 'owner', reviewedByUid: 'moderator', status: 'approved', name: 'Test spot', ...overrides };
  const calls = [];
  const docs = ['owner', ...Array.from({ length: 650 }, (_, i) => `user${i}`)]
    .map(id => ({ id }));
  const db = { collection: name => ({
    get: async () => ({ docs }),
    doc: id => ({ get: async () => ({ exists: true, data: () => name === 'spots' ? spot : { role: 'moderator' } }) }),
  }) };
  const context = vm.createContext({
    admin: { apps: [true], firestore: () => db }, console,
    capture: async options => { calls.push(options); return options.userId === 'owner' ? 0 : 1; },
  });
  const source = fs.readFileSync(path.join(__dirname, '../api/push-notification.js'), 'utf8')
    .replace(/^import .*;\r?\n/gm, '')
    .replace(/export default /g, '').replace(/export /g, '');
  vm.runInContext(source + '\nsendPushToUser = capture; spotPublicationPushAllowed = async () => true;', context);
  return { calls, context };
}

test('approval dispatch includes the full audience even when the owner receives no push', async () => {
  const { calls, context } = fixture();
  const results = await context.handleSpotDecision('moderator', { spotId: 's', status: 'approved' });
  assert.equal(calls.length, 651);
  assert.equal(results.reduce((a, b) => a + b, 0), 650);
  assert.equal(calls[0].settingName, 'reviewNotifications');
  assert.equal(calls.at(-1).userId, 'user649');
  assert.equal(calls.at(-1).settingName, 'newSpotNotifications');
  assert.equal(calls.at(-1).notificationId, 'new_spot_s_user649');
});

test('rejection only notifies the owner', async () => {
  const { calls, context } = fixture({ status: 'rejected' });
  await context.handleSpotDecision('moderator', { spotId: 's', status: 'rejected' });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].userId, 'owner');
});

test('another reviewer cannot publish a decision', async () => {
  const { calls, context } = fixture();
  await context.handleSpotDecision('other-moderator', { spotId: 's', status: 'approved' });
  assert.equal(calls.length, 0);
});

test('creation and approval use the same per-recipient publication claim', async () => {
  const { calls, context } = fixture({ addedByUid: 'moderator', ownerUid: 'owner' });
  await context.handleNewSpot('moderator', { spotId: 's' });
  const creation = calls.find(call => call.userId === 'user649');
  calls.length = 0;
  await context.handleSpotDecision('moderator', { spotId: 's', status: 'approved' });
  const approval = calls.find(call => call.userId === 'user649');
  assert.equal(creation.deliveryKey, approval.deliveryKey);
  assert.equal(creation.notificationId, approval.notificationId);
});

test('the redundant creation request from a non-owner moderator has no audience', async () => {
  const { calls, context } = fixture();
  await context.handleNewSpot('moderator', { spotId: 's' });
  assert.equal(calls.length, 0);
});
