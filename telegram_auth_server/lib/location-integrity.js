const {admin, db} = require('./firebase-admin');
const {distanceMeters} = require('./spot-visits');

// Only the authenticated user's own samples are assessed. A GPS-quality failure
// is not evidence of cheating. Keep one private sample, never a public trail.
async function assessLocation(uid, fix, now = Date.now()) {
  if (!fix || !Number.isFinite(fix.latitude) || !Number.isFinite(fix.longitude) ||
      Math.abs(fix.latitude) > 90 || Math.abs(fix.longitude) > 180 ||
      !Number.isFinite(fix.recordedAtMillis) || Math.abs(now - fix.recordedAtMillis) > 150000 ||
      !Number.isFinite(fix.accuracy) || fix.accuracy < 0 || fix.accuracy > 100) return false;
  const ref = db.collection('location_integrity').doc(uid);
  const decision = await db.runTransaction(async tx => {
    const previous = (await tx.get(ref)).data() || {};
    let reason = fix.isMocked === true ? 'Device reported a mock GPS location' : null;
    if (!reason && fix.isMocked !== false) return {accepted: false};
    const seconds = (fix.recordedAtMillis - (previous.recordedAtMillis || 0)) / 1000;
    if (!reason && seconds < 0) return {accepted: false};
    if (!reason && previous.lat != null && seconds >= 0 && seconds < 1800) {
      const meters = distanceMeters(previous, {lat: fix.latitude, lng: fix.longitude});
      // Deliberately beyond aircraft speeds, with a generous distance tolerance.
      if (meters > 5000 && meters / Math.max(1, seconds) > 400)
        reason = 'Impossible travel between recent GPS checks';
    }
    const alert = !!reason && now - (previous.lastAlertAtMillis || 0) >= 86400000;
    tx.set(ref, {
      ...(!reason ? {lat: fix.latitude, lng: fix.longitude, recordedAtMillis: fix.recordedAtMillis} : {}),
      ...(alert ? {lastAlertAtMillis: now, reason} : {}),
      expiresAtMillis: now + 86400000,
    }, {merge: true});
    return {accepted: !reason, alert, reason};
  });
  if (decision.alert) {
    const [profile, admins] = await Promise.all([
      db.collection('users').doc(uid).get(), db.collection('users').where('role', '==', 'admin').get(),
    ]);
    const nickname = String(profile.data()?.username || profile.data()?.name || uid).slice(0, 100);
    const day = Math.floor(now / 86400000);
    const data = {type: 'location_suspicion', suspectUid: uid, username: nickname, reason: decision.reason};
    for (const row of admins.docs) {
      if (row.data().deleted || row.data().banned) continue;
      const id = `location_suspicion_${uid}_${day}_${row.id}`;
      const title = 'Suspicious location activity';
      const body = `@${nickname}: ${decision.reason}. Review required; this is not a confirmed cheat.`;
      await db.collection('admin_notifications').doc(id).set({userId: row.id, ...data, title, body,
        read: false, createdAt: admin.firestore.FieldValue.serverTimestamp(), createdAtMillis: now});
      if (admin.messaging) {
        try {
          const {sendPushToUser} = await import('../api/push-notification.js');
          await sendPushToUser({userId: row.id, title, body, data, notificationCollection: 'admin_notifications',
            notificationId: id, deliveryKey: id, settingName: 'adminNotifications'});
        } catch (error) { console.error('Location review push failed; bell saved', error.message); }
      }
    }
  }
  return decision.accepted;
}
module.exports = {assessLocation};
