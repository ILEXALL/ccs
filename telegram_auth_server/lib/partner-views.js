const crypto = require('node:crypto');
async function recordPartnerView(db, uid, partnerId) {
  if (typeof partnerId !== 'string' || !/^[\w-]{1,128}$/.test(partnerId)) throw Object.assign(new Error('Invalid partner'), {status:400});
  const partnerRef = db.collection('partners').doc(partnerId);
  const viewRef = db.collection('partner_views').doc(crypto.createHash('sha256').update(JSON.stringify([uid,partnerId])).digest('hex'));
  return db.runTransaction(async tx => {
    const [partnerDoc, viewDoc, userDoc] = await Promise.all([
      tx.get(partnerRef), tx.get(viewRef), tx.get(db.collection('users').doc(uid)),
    ]);
    const user = userDoc.data(), partner = partnerDoc.data();
    if (!user || user.deleted || user.banned || user.deletionRequestedAt) throw Object.assign(new Error('Account unavailable'), {status:403});
    if (!partner || partner.active === false) throw Object.assign(new Error('Partner unavailable'), {status:404});
    const current = Number.isSafeInteger(partner.uniqueViews) && partner.uniqueViews >= 0 ? partner.uniqueViews : 0;
    if (viewDoc.exists) return current;
    tx.create(viewRef, {userId:uid, partnerId, viewedAtMillis:Date.now()});
    tx.update(partnerRef, {uniqueViews:current+1});
    return current+1;
  });
}
module.exports = {recordPartnerView};
