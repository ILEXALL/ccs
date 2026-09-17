const { admin, db } = require('./firebase-admin');
const LEASE_MS = 90000;
const text = value => typeof value === 'string' ? value.trim() : '';
const millis = value => value && typeof value.toMillis === 'function' ? value.toMillis() : 0;

function canReview(user, spot, now) {
  if (!user || user.deleted === true || (user.banned === true &&
      !(millis(user.bannedUntil) > 0 && millis(user.bannedUntil) < now))) return false;
  if (user.role === 'admin') return true;
  return user.role === 'moderator' && text(spot.countryCode) !== '' &&
    Array.isArray(user.moderatorCountryCodes) &&
    user.moderatorCountryCodes.map(code => text(code).toUpperCase())
      .includes(text(spot.countryCode).toUpperCase());
}

async function spotReviewAction({ actor, body }) {
  const spotId = text(body.spotId);
  const sessionId = text(body.sessionId);
  const operation = text(body.operation);
  if (!spotId || spotId.includes('/') || !/^[A-Za-z0-9_-]{16,100}$/.test(sessionId) ||
      !['acquire', 'renew', 'release', 'decide'].includes(operation)) {
    throw new Error('Invalid spot review request');
  }
  const spotRef = db.collection('spots').doc(spotId);
  const lockRef = db.collection('spot_review_locks').doc(spotId);
  const userRef = db.collection('users').doc(actor.uid);
  return db.runTransaction(async transaction => {
    const [spotSnapshot, lockSnapshot, userSnapshot] = await Promise.all([
      transaction.get(spotRef), transaction.get(lockRef), transaction.get(userRef),
    ]);
    const now = Date.now();
    const lock = lockSnapshot.data() || {};
    const owns = lock.reviewerUid === actor.uid && lock.sessionId === sessionId;
    const alive = millis(lock.expiresAt) > now;
    if (operation === 'release') {
      if (owns) transaction.delete(lockRef);
      return { released: owns };
    }
    if (!spotSnapshot.exists) throw new Error('Spot is no longer available');
    const spot = spotSnapshot.data();
    const user = userSnapshot.data();
    if (!userSnapshot.exists || !canReview(user, spot, now)) {
      throw new Error('No permission to review this spot');
    }
    if (operation === 'acquire') {
      if (alive && !owns) return {
        acquired: false, reviewerUsername: text(lock.reviewerUsername),
      };
      transaction.set(lockRef, {
        reviewerUid: actor.uid, reviewerUsername: text(user.username), sessionId,
        expiresAt: admin.firestore.Timestamp.fromMillis(now + LEASE_MS),
        heartbeatAt: admin.firestore.Timestamp.fromMillis(now),
        decision: owns ? text(lock.decision) : '',
      });
      return { acquired: true, leaseMillis: LEASE_MS };
    }
    if (!owns || !alive) throw new Error('Review lock expired or belongs to another reviewer');
    if (operation === 'renew') {
      transaction.update(lockRef, {
        expiresAt: admin.firestore.Timestamp.fromMillis(now + LEASE_MS),
        heartbeatAt: admin.firestore.Timestamp.fromMillis(now),
      });
      return { renewed: true, leaseMillis: LEASE_MS };
    }
    const status = text(body.status);
    const reason = status === 'rejected' ? text(body.rejectionReason) : '';
    if (!['approved', 'rejected'].includes(status) ||
        (status === 'rejected' && (!reason || reason.length > 2000))) {
      throw new Error('Invalid review decision');
    }
    if (lock.decision) {
      if (lock.decision === status && spot.status === status) return { alreadyDecided: true };
      throw new Error('This review already has a decision');
    }
    if (!['pending', 'edited', 'rejected'].includes(spot.status)) {
      throw new Error('Spot is no longer awaiting this review');
    }
    if (spot.visibility === 'group') {
      const topicRef = db.collection('forum_topics').doc(`temporary_spot_${spotId}`);
      const topicSnapshot = await transaction.get(topicRef);
      transaction.set(topicRef, {
        ...(!topicSnapshot.exists ? {
          title: spot.name, description: spot.description || 'Group event', category: 'Meets & Events', categoryId: 'meets_events',
          authorId: spot.addedByUid, authorName: spot.addedBy, avatarUrl: spot.photoUrl || '',
          repliesCount: 0, isPinned: false, source: 'temporary_spot', isSpotTopic: true,
          spotId, temporarySpotId: spotId, createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastReplyAt: admin.firestore.FieldValue.serverTimestamp(),
        } : {}),
        visibility: 'group', sharedGroupIds: spot.sharedGroupIds, sharedGroups: spot.sharedGroups || [],
        countryCode: spot.countryCode, temporarySpotStartsAt: spot.startsAt,
        temporarySpotExpiresAt: spot.expiresAt, autoExpiresAt: spot.expiresAt,
        status, rejectionReason: reason, reviewedBy: actor.uid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      for (const groupId of spot.sharedGroupIds) {
        transaction.set(db.collection('chats').doc(groupId).collection('spot_links').doc(spotId), {
          spotId, authorUid: spot.addedByUid, published: status === 'approved',
        });
      }
    }
    transaction.update(spotRef, {
      status, rejectionReason: reason,
      reviewedBy: text(user.username), reviewedByUid: actor.uid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(spot.editReviewStatus === 'pending' ? { editReviewStatus: status } : {}),
    });
    // Keep ownership while the review screen completes notification work.
    transaction.update(lockRef, { decision: status });
    return { alreadyDecided: false };
  });
}

module.exports = { spotReviewAction };
