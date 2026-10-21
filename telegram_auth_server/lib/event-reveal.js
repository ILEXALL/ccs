const crypto = require('node:crypto');
const millis = value => value?.toMillis?.() ?? (typeof value === 'number' ? value : 0);
function revealIsDue(spot, now, since) {
  const reveal = millis(spot?.showOnMapAt);
  return !!spot && spot.isTemporary === true && spot.status === 'approved' && spot.deleted !== true &&
    (!spot.visibility || spot.visibility === 'public') && reveal >= since && reveal > 0 &&
    reveal <= now && millis(spot.expiresAt) > now && millis(spot.startsAt) > 0;
}
function reminderIsDue(spot, now, since) {
  const start = millis(spot?.startsAt);
  const reminder = start - 5 * 60 * 60 * 1000;
  return !!spot && spot.isTemporary === true && spot.status === 'approved' && spot.deleted !== true &&
    (!spot.visibility || spot.visibility === 'public') && start > 0 && reminder >= since &&
    reminder <= now && now < start && millis(spot.expiresAt) > now;
}
function notificationJob(spot, id, kind) {
  const name = String(spot.name || 'Event');
  if (kind === 'reminder') {
    const start = millis(spot.startsAt);
    return {due: reminderIsDue, key: `temporary_spot_reminder:${id}:${start}`,
      notificationId: `temporary_spot_reminder_${id}_${start}`,
      title: 'Event reminder', body: `${name} starts in ${Math.max(1, Math.ceil((start - Date.now()) / 60000))} minutes.`,
      data: {type: 'temporary_spot_today', preferenceKey: 'newSpotNotifications',
        spotId: id, spotName: name, startsAtMillis: start}};
  }
  return {due: revealIsDue, key: 'event_location_revealed:' + id,
    notificationId: 'event_reveal_' + id,
    title: 'Event location revealed', body: name + ' — the location is now available on the map.',
    data: {type: 'event_location_revealed', preferenceKey: 'newSpotNotifications', spotId: id, spotName: name}};
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
async function dispatchEventNotifications({db, send, countryKey, since, now = Date.now(), budgetMs = 40000, kinds = ['reminder', 'reveal'], spotId}) {
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
    const events = spotId ? [await db.collection('spots').doc(spotId).get()]
      : (await db.collection('spots').where('isTemporary','==',true).get()).docs;
    for (const event of events) {
      if (Date.now() >= deadline) break;
      const spot=event.data();
      for (const kind of kinds) {
        const job=notificationJob(spot || {},event.id,kind);
        if (!job.due(spot,now,since) || !countryKey(eventCountry(spot))) continue;
        const key=job.key;
        const stateRef=db.collection('event_reveal_jobs').doc(crypto.createHash('sha256').update(key).digest('hex'));
        let state=(await stateRef.get()).data() || {};
        if (state.complete) continue;
        while (Date.now()<deadline) {
          // Recheck approval/visibility before each recipient page.
          const current=(await db.collection('spots').doc(event.id).get()).data();
          if (!job.due(current,Date.now(),since) || notificationJob(current,event.id,kind).key !== key) break;
          let query=db.collection('users').orderBy('__name__').limit(25);
          if (state.cursor) query=query.startAfter(state.cursor);
          const users=(await query.get()).docs;
          const results=await Promise.allSettled(users.map(async doc => {
            const user=doc.data();
            if (!recipientMatches(user,current,countryKey)) return;
            const message=notificationJob(current,event.id,kind);
            await send({userId:doc.id,settingName:'newSpotNotifications',
              communityCountry:eventCountry(current),deliveryKey:key,
              notificationId:message.notificationId+'_'+doc.id,
              title:message.title,body:message.body,data:message.data});
            processed++;
          }));
          const failed=results.find(r=>r.status==='rejected');
          if (failed) throw failed.reason;
          state={cursor:users.at(-1)?.id || state.cursor || '',complete:users.length<25};
          await db.runTransaction(async tx => tx.set(stateRef,state));
          if (state.complete) break;
        }
      }
    }
    return {ok:true,processed};
  } finally {
    await db.runTransaction(async tx => {
      if ((await tx.get(leaseRef)).data()?.token===token) tx.set(leaseRef,{leaseUntil:0,lastRunAt:now},{merge:true});
    });
  }
}
const dispatchEventReveals = args => dispatchEventNotifications({...args, kinds: ['reveal']});
module.exports={revealIsDue,reminderIsDue,eventCountry,recipientMatches,dispatchEventReveals,dispatchEventNotifications};
