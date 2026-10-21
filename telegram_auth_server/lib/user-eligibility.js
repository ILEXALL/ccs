const {calculateLevel} = require('./xp/xp-engine');
const text = value => typeof value === 'string' ? value.trim() : '';
const uploadedPhoto = value => /^https:\/\/[^\s/]+\/[^\s]+$/i.test(text(value));

function eligibleForVerification(user, xpTotal) {
  if (!user || user.deleted || user.banned || user.verified === true) return false;
  // Preserve an explicit staff revocation rather than immediately undoing it.
  if (user.verified === false && text(user.verifiedUpdatedByUid) && user.verifiedUpdatedByUid !== 'system') return false;
  if (calculateLevel(xpTotal) < 5) return false;
  if (![user.photoUrl, user.avatarPath].some(uploadedPhoto)) return false;
  return Array.isArray(user.garage) && user.garage.some(car => car &&
    text(car.description) && [car.photoPath, ...(Array.isArray(car.photoPaths) ? car.photoPaths : [])].some(uploadedPhoto));
}

function verificationFields(user, xpTotal, timestamp) {
  return eligibleForVerification(user, xpTotal) ? {
    verified: true, verifiedUpdatedByUid: 'system',
    verifiedUpdatedBy: 'Automatic verification', verifiedUpdatedAt: timestamp,
  } : null;
}

async function syncAutomaticVerification(db, admin, uid) {
  const userRef = db.collection('users').doc(uid);
  return db.runTransaction(async tx => {
    const user = await tx.get(userRef);
    const stats = await tx.get(db.collection('xp_user_stats').doc(uid));
    if (!user.exists || !stats.exists) return false;
    const fields = verificationFields(user.data(), stats.data().xpTotal,
      admin.firestore.FieldValue.serverTimestamp());
    if (!fields) return false;
    tx.update(userRef, fields);
    return true;
  });
}

function manuallyApprovedPermanentSpot(spot, uid) {
  return spot.addedByUid === uid && spot.status === 'approved' &&
    spot.isTemporary !== true && spot.deleted !== true &&
    (!spot.approvalMethod || spot.approvalMethod === 'manual') &&
    text(spot.reviewedByUid) !== '' && spot.reviewedByUid !== uid &&
    spot.reviewedByUid !== 'system' && !!spot.reviewedAt;
}

module.exports = {eligibleForVerification, verificationFields, syncAutomaticVerification, manuallyApprovedPermanentSpot};
