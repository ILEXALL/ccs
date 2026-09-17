const { db } = require('./firebase-admin');
function groupSpot(spot) { return spot && spot.visibility === 'group'; }
async function groupSpotMemberIds(spot) {
  if (!groupSpot(spot)) return null;
  const ids = Array.isArray(spot.sharedGroupIds) ? [...new Set(spot.sharedGroupIds)] : [];
  if (!ids.length || ids.length > 8 || ids.some(id => typeof id !== 'string' || !id || id.includes('/'))) return [];
  const groups = await Promise.all(ids.map(id => db.collection('chats').doc(id).get()));
  return [...new Set(groups.flatMap(doc => doc.exists && doc.data().isGroup === true ? doc.data().memberIds || [] : []))];
}
module.exports = { groupSpot, groupSpotMemberIds };
