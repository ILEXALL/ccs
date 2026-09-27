const {createHash} = require('node:crypto');
const TERMS_VERSION = '2026-09-24';
const CACHE_CONTROL = 'public, max-age=300, must-revalidate';
const fail = (status, message) => { throw Object.assign(new Error(message), {status}); };
const uploadId = key => createHash('sha256').update(key).digest('hex');

function validateUpload(body) {
  const key = body?.path;
  // Reject ambiguous keys instead of silently rewriting the caller's target.
  if (typeof key !== 'string' || key.length > 1000 ||
      !/^(users|garage|spots)\/[A-Za-z0-9_-]+\/[A-Za-z0-9_./-]+$/.test(key) ||
      key.split('/').some(part => !part || part === '.' || part === '..')) fail(400, 'Invalid upload path');
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(body.contentType)) fail(400, 'Invalid content type');
  return {key, contentType: body.contentType, cacheControl: CACHE_CONTROL};
}

// Ownership commits before a signed URL is returned, including abandoned uploads.
async function reserveUpload({db, uid, key, now = Date.now}) {
  const [root, owner] = key.split('/');
  if (root !== 'spots' && owner !== uid) fail(403, 'Upload path belongs to another account');
  if (root === 'spots' && (key.split('/')[2] !== 'users' || key.split('/')[3] !== uid)) {
    fail(403, 'Spot uploads must use the current account namespace');
  }
  const ref = db.collection('media_uploads').doc(uploadId(key));
  await db.runTransaction(async tx => {
    const refs = [db.doc(`account_deletions/${uid}`), db.doc(`users/${uid}`),
      db.doc(`users/${uid}/legal_acceptances/${TERMS_VERSION}`), ref];
    if (root === 'spots') refs.push(db.doc(`spots/${owner}`), db.doc(`media_spot_reservations/${owner}`));
    const [deletion, actor, consent, previous, spot, reservation] = await tx.getAll(...refs);
    if (deletion.exists || !actor.exists || actor.data().deleted === true || actor.data().banned === true) fail(403, 'Account unavailable');
    if (consent.data()?.termsVersion !== TERMS_VERSION) fail(403, 'Accept the current terms before uploading');
    if (previous.exists && previous.data().uid !== uid) fail(409, 'Choose a new filename for this upload');
    if (root === 'spots') {
      const data = spot.data();
      if (spot.exists) {
        if (data.addedByUid !== uid && data.ownerUid !== uid && actor.data().role !== 'admin') fail(403, 'No permission to upload to this spot');
        const owners = [...new Set([data.addedByUid, data.ownerUid].filter(id => typeof id === 'string' && id && !id.includes('/')))];
        for (const id of owners) {
          if ((await tx.get(db.doc(`account_deletions/${id}`))).exists) fail(403, 'Spot deletion in progress');
        }
      } else if (reservation.exists && reservation.data().uid !== uid) {
        fail(403, 'This spot upload is reserved by another account');
      }
      if (!spot.exists && !reservation.exists) tx.create(db.doc(`media_spot_reservations/${owner}`), {uid, createdAt: now()});
    }
    tx.set(ref, {uid, key, updatedAt: now()});
  });
}

function createUploadHandler({auth, db, sign, now = Date.now}) {
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method !== 'POST') return res.status(405).json({error: 'Method not allowed'});
    try {
      const bearer = req.headers.authorization || '';
      if (!bearer.startsWith('Bearer ')) return res.status(401).json({error: 'Sign in required'});
      let token;
      try { token = await auth.verifyIdToken(bearer.slice(7), true); }
      catch (_) { return res.status(401).json({error: 'Sign in required'}); }
      const upload = validateUpload(req.body);
      // Sign before the transaction to bound expiry even if its checks retry.
      // No signed URL leaves the handler until authorization/ownership commits.
      const signed = await sign(upload);
      await reserveUpload({db, uid: token.uid, key: upload.key, now});
      return res.status(200).json({...signed, key: upload.key, cacheControl: CACHE_CONTROL});
    } catch (error) {
      return res.status(error.status || 500).json({error: error.status ? error.message : 'Could not create R2 upload URL'});
    }
  };
}
module.exports = {validateUpload, reserveUpload, createUploadHandler, uploadId, CACHE_CONTROL, TERMS_VERSION};
