function uploadPath(value) {
  if (typeof value !== 'string' || value.length > 512 ||
      !/^(users|garage|spots)\/[A-Za-z0-9_-]+\/[A-Za-z0-9_./-]+$/.test(value) ||
      value.split('/').some(part => !part || part === '.' || part === '..')) return null;
  return value;
}

async function authorizeUpload(db, uid, path) {
  const [deletion, actor] = await Promise.all([
    db.collection('account_deletions').doc(uid).get(),
    db.collection('users').doc(uid).get(),
  ]);
  if (deletion.exists) return 'Account deletion in progress';
  const user = actor.data() || {};
  const bannedUntil = user.bannedUntil?.toMillis?.() || 0;
  if (user.deleted === true || (user.banned === true && (!bannedUntil || bannedUntil > Date.now()))) {
    return 'Account is not active';
  }
  const [root, owner] = path.split('/');
  // Initial profile avatars are uploaded before the profile exists.
  if (root === 'users' || root === 'garage') {
    return owner === uid ? null : 'Upload path belongs to another account';
  }
  const spot = await db.collection('spots').doc(owner).get();
  // New spot photos use users/{uid}/spot_photos, not unclaimed shared keys.
  if (!spot.exists) return 'Spot does not exist';
  return spot.data().addedByUid === uid || spot.data().ownerUid === uid || user.role === 'admin'
    ? null : 'No permission to upload to this spot';
}

module.exports = {uploadPath, authorizeUpload};
