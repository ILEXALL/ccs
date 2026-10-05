const crypto = require('node:crypto');
const millis = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
// Each task has its own continuous dwell evidence. Being nearer another spot
// must not prevent an otherwise eligible user from completing this task.
async function prepareNearbyAdminRewards(db, tx, {userId, user, position, sample, now, session, candidates, distanceMeters, coordinates}) {
  const progress = {}, writes = [];
  let existingClaim = false;
  for (const candidate of candidates) {
    const reward = (await tx.get(db.collection('admin_rewards').doc(candidate.id))).data();
    if (!reward?.enabled || now < Math.max(reward.startsAt, reward.createdAt) || now >= reward.endsAt) continue;
    const spot = (await tx.get(db.collection('spots').doc(reward.spotId))).data();
    const target = coordinates(spot);
    if (!spot || !target || spot.deleted || spot.status !== 'approved' || distanceMeters(position,target)>100 ||
        (spot.verifiedOnly && !user.verified && !['admin','moderator'].includes(user.role)) ||
        (spot.isTemporary && (millis(spot.startsAt)>now || millis(spot.expiresAt)<=now))) continue;
    if (spot.visibility === 'group') {
      let member=false;
      for(const id of (spot.sharedGroupIds||[]).slice(0,8)) {
        if(typeof id!=='string' || id.includes('/')) continue;
        const group=(await tx.get(db.collection('chats').doc(id))).data();
        if(group?.isGroup && group.memberIds?.includes(userId)) member=true;
      }
      if(!member) continue;
    }
    const ref=db.collection('admin_reward_claims').doc(crypto.createHash('sha256').update(`${userId}|${candidate.id}`).digest('hex'));
    if((await tx.get(ref)).exists) {existingClaim=true; continue;}
    const old=session.rewardDwell?.[candidate.id];
    const continuous=old && now>=old.lastSeenAt && now-old.lastSeenAt<=60000 && sample>=old.lastSampleAt && sample-old.lastSampleAt<=60000;
    const elapsedMs=continuous?Math.min(300000,(old.elapsedMs||0)+Math.max(0,Math.min(now-old.lastSeenAt,sample-old.lastSampleAt))):0;
    progress[candidate.id]={elapsedMs,lastSeenAt:now,lastSampleAt:sample};
    if(elapsedMs>=300000) writes.push({ref,data:{userId,rewardId:candidate.id,xp:reward.xp,title:reward.title,completedAt:now}});
  }
  return {progress, claimed:existingClaim || writes.length>0, write:()=>{for(const item of writes) tx.create(item.ref,item.data);}};
}
module.exports={prepareNearbyAdminRewards};
