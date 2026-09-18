const {admin, db} = require('../lib/firebase-admin');
const {recordSpotVisit} = require('../lib/spot-visits');

module.exports = async (req, res) => {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ok: false}); }
  let token;
  try {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return res.status(401).json({ok: false});
    token = await admin.auth().verifyIdToken(header.slice(7));
  } catch (_) { return res.status(401).json({ok: false}); }
  try {
    const result = await recordSpotVisit(db, token.uid, req.body?.spotId);
    return res.status(200).json({ok: true, result});
  } catch (_) { return res.status(403).json({ok: false, error: 'Visit could not be recorded'}); }
};
