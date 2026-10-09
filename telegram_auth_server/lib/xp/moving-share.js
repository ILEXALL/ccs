const {db} = require('../firebase-admin');
const {distanceMeters} = require('../spot-visits');
const {awardXp} = require('./xp-firestore');
const ms = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
const HOUR = 3600000;

// Count only observed movement between fresh stored sharing samples. Client
// counters, claimed durations and phone calendar dates are never accepted.
function advanceMovingShare(previous, live, now) {
  const valid = live && live.isMocked === false && Number.isFinite(live.lat) &&
    Number.isFinite(live.lng) && Math.abs(live.lat)<=90 && Math.abs(live.lng)<=180 &&
    Number.isFinite(live.accuracy) && live.accuracy>=0 && live.accuracy<=35 &&
    ms(live.expiresAt)>now && ms(live.updatedAt)<=now && now-ms(live.updatedAt)<=60000 &&
    Number.isFinite(live.recordedAtMillis) && live.recordedAtMillis<=now &&
    now-live.recordedAtMillis<=60000;
  const total = previous.movingMs || 0;
  if (!valid) return {...previous,lastAt:0,movingMs:total};
  const sample=live.recordedAtMillis;
  if(sample <= (previous.sample || 0)) return previous;
  const elapsed=now-(previous.lastAt || 0), delta=sample-(previous.sample || 0);
  let credit=0;
  if(previous.lastAt>0 && elapsed>0 && elapsed<=90000 && delta>0 && delta<=90000 &&
      previous.expiresAt>=now) {
    const distance=distanceMeters(previous,live);
    const seconds=delta/1000;
    // Reject stationary jitter, poor fixes and implausible driving jumps.
    if(distance>=Math.max(15,previous.accuracy+live.accuracy) &&
       distance/seconds>=1 && distance/seconds<=70) credit=Math.min(elapsed,delta);
  }
  return {...previous,lat:live.lat,lng:live.lng,accuracy:live.accuracy,
    sample,lastAt:now,expiresAt:ms(live.expiresAt),movingMs:total+credit};
}
async function recordMovingShare(userId, now=Date.now()) {
  const ref=db.collection('moving_share_rewards').doc(userId);
  const state=await db.runTransaction(async tx=>{
    const previous=(await tx.get(ref)).data() || {};
    const live=(await tx.get(db.collection('live_locations').doc(userId))).data();
    const user=(await tx.get(db.collection('users').doc(userId))).data();
    if(!user || user.deleted || user.banned) return previous;
    const next=advanceMovingShare(previous,live,now);
    tx.set(ref,next);
    return next;
  });
  const hours=Math.floor((state.movingMs || 0)/HOUR);
  // Retry unpaid hours after a failed request. Stable IDs prevent double awards.
  for(let hour=(state.awardedHours || 0)+1;hour<=Math.min(hours,(state.awardedHours || 0)+24);hour++){
    const result=await awardXp({userId,action:'sharing.hour',objectType:'live_sharing',
      objectId:'moving-hours',stage:String(hour),amount:100,
      metadata:{reason:'One hour moving while sharing location',hour}},{now:new Date(now)});
    if(!['confirmed','pending'].includes(result.status)) break;
    await db.runTransaction(async tx=>{
      const current=(await tx.get(ref)).data() || {};
      tx.set(ref,{awardedHours:Math.max(current.awardedHours || 0,hour)},{merge:true});
    });
  }
  return {movingMs:state.movingMs || 0,hours};
}
module.exports={advanceMovingShare,recordMovingShare};
