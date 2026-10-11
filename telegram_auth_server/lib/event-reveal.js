const crypto = require('node:crypto');
const millis = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
function revealIsDue(spot, now, since) {
  const reveal = millis(spot?.showOnMapAt);
  return !!spot && spot.isTemporary === true && spot.status === 'approved' && spot.deleted !== true &&
    (!spot.visibility || spot.visibility === 'public') && reveal >= since && reveal > 0 &&
    reveal <= now && millis(spot.expiresAt) > now && millis(spot.startsAt) > 0;
}
function eventCountry(spot) {
  return typeof spot.countryCode === 'string' && spot.countryCode.trim()
    ? spot.countryCode.trim() : String(spot.cityCountry || '').split(',').at(-1).trim();
}
function recipientMatches(user, spot, countryKey) {
  const target = countryKey(eventCountry(spot));
  // Unknown countries fail closed. Use profile country, not map filter choices.
  return !!target && countryKey(user.country || '') === target && user.deleted !== true &&
    (!spot.verifiedOnly || user.verified === true || ['admin','moderator'].includes(user.role));
}

// Resumable pages: no 500-user audience cap, no duplicate delivery on retries.
// The shared lease prevents concurrent scheduler runs from racing their cursors.
async function dispatchEventReveals({db, send, countryKey, since, now = Date.now(), budgetMs = 40000}) {
  const leaseRef = db.collection('event_reveal_jobs').doc('scheduler');
  const token = crypto.randomUUID();
  const claimed = await db.runTransaction(async tx => {
    const state = (await tx.get(leaseRef)).data() || {};
    if (state.leaseUntil > now) return false;
    tx.set(leaseRef, {token, leaseUntil: now + 120000}, {merge:true});
    return true;
  });
  if (!claimed) return {ok:true, busy:true, processed:0};
  let processed=0;
  const deadline=Date.now()+budgetMs;
  try {
    const events = (await db.collection('spots').where('isTemporary','==',true).get()).docs;
    for (const event of events) {
      if (Date.now() >= deadline) break;
      const spot=event.data();
      if (!revealIsDue(spot,now,since) || !countryKey(eventCountry(spot))) continue;
      const key='event_location_revealed:'+event.id;
      const stateRef=db.collection('event_reveal_jobs').doc(crypto.createHash('sha256').update(key).digest('hex'));
      let state=(await stateRef.get()).data() || {};
      if (state.complete) continue;
      while (Date.now()<deadline) {
        // Recheck approval/visibility before each recipient page.
        const current=(await db.collection('spots').doc(event.id).get()).data();
        if (!revealIsDue(current,Date.now(),since)) break;
        let query=db.collection('users').orderBy('__name__').limit(25);
        if (state.cursor) query=query.startAfter(state.cursor);
        const users=(await query.get()).docs;
        const results=await Promise.allSettled(users.map(async doc => {
          const user=doc.data();
          if (!recipientMatches(user,current,countryKey)) return;
          const name=String(current.name || 'Event');
          await send({userId:doc.id,settingName:'newSpotNotifications',
            communityCountry:eventCountry(current),deliveryKey:key,
            notificationId:'event_reveal_'+event.id+'_'+doc.id,
            title:'Event location revealed',body:name+' — the location is now available on the map.',
            data:{type:'event_location_revealed',preferenceKey:'newSpotNotifications',spotId:event.id,spotName:name}});
          processed++;
        }));
        const failed=results.find(r=>r.status==='rejected');
        if (failed) throw failed.reason;
        state={cursor:users.at(-1)?.id || state.cursor || '',complete:users.length<25};
        await db.runTransaction(async tx => tx.set(stateRef,state));
        if (state.complete) break;
      }
    }
    return {ok:true,processed};
  } finally {
    await db.runTransaction(async tx => {
      if ((await tx.get(leaseRef)).data()?.token===token) tx.set(leaseRef,{leaseUntil:0,lastRunAt:now},{merge:true});
    });
  }
}
module.exports={revealIsDue,eventCountry,recipientMatches,dispatchEventReveals};
