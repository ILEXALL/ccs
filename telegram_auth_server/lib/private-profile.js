// This document is never readable by other users. Keep it under users so
// recursive account deletion also removes delivery tokens and account email.
const PRIVATE_FIELDS = ['email', 'fcmTokens', 'fcmTokenUpdatedAt', 'lastFcmTokenPlatform'];
const privateProfileRef = (db, uid) => db.collection('users').doc(uid).collection('private').doc('account');

async function deliveryTokens(db, uid, legacy = {}) {
  const snapshot = await privateProfileRef(db, uid).get();
  // Temporary migration fallback: remove only after all public records are moved.
  const current = snapshot.data()?.fcmTokens;
  const values = [...(Array.isArray(current) ? current : []),
    ...(Array.isArray(legacy.fcmTokens) ? legacy.fcmTokens : [])];
  return [...new Set(values
    .filter(value => typeof value === 'string' && value.trim()))];
}

async function removeDeliveryTokens(db, uid, tokens) {
  const publicRef = db.collection('users').doc(uid);
  const privateRef = privateProfileRef(db, uid);
  await db.runTransaction(async tx => {
    const [publicDoc, privateDoc] = await tx.getAll(publicRef, privateRef);
    for (const [ref, snapshot] of [[publicRef, publicDoc], [privateRef, privateDoc]]) {
      const existing = snapshot.data()?.fcmTokens;
      // Never recreate a public token field after the final migration.
      if (Array.isArray(existing)) tx.update(ref, {fcmTokens: existing.filter(token => !tokens.includes(token))});
    }
  });
}

async function migratePrivateProfile(db, admin, ref, apply = false) {
  return db.runTransaction(async transaction => {
    const publicSnapshot = await transaction.get(ref);
    const data = publicSnapshot.data() || {};
    const fields = PRIVATE_FIELDS.filter(field => Object.hasOwn(data, field));
    if (!fields.length || !apply) return fields.length > 0;
    const privateRef = privateProfileRef(db, ref.id);
    const existing = (await transaction.get(privateRef)).data() || {};
    const moved = Object.fromEntries(fields.map(field => [field, data[field]]));
    // Preserve tokens registered by the updated app during the migration.
    if (Array.isArray(data.fcmTokens) || Array.isArray(existing.fcmTokens)) {
      moved.fcmTokens = [...new Set([
        ...(Array.isArray(data.fcmTokens) ? data.fcmTokens : []),
        ...(Array.isArray(existing.fcmTokens) ? existing.fcmTokens : []),
      ])];
    }
    transaction.set(privateRef, {...moved, ...existing,
      ...(moved.fcmTokens ? {fcmTokens: moved.fcmTokens} : {})}, {merge: true});
    transaction.update(ref, Object.fromEntries(fields.map(field => [field, admin.firestore.FieldValue.delete()])));
    return true;
  });
}

module.exports = {PRIVATE_FIELDS, privateProfileRef, deliveryTokens, removeDeliveryTokens, migratePrivateProfile};
