const {admin, db} = require('../lib/firebase-admin');
const {createGroupSpot} = require('../lib/group-spot-create');

module.exports = async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({error: 'Method not allowed'});
  const bearer = req.headers.authorization || '';
  if (!bearer.startsWith('Bearer ')) return res.status(401).json({error: 'Sign in required'});
  let token;
  try { token = await admin.auth().verifyIdToken(bearer.slice(7), true); }
  catch (_) { return res.status(401).json({error: 'Sign in required'}); }
  try {
    const result = await createGroupSpot({db, firestore: admin.firestore, uid: token.uid,
      body: req.body, publicBaseUrl: process.env.R2_PUBLIC_BASE_URL});
    return res.json(result);
  } catch (error) {
    return res.status(error.status || 500).json({error: error.status ? error.message : 'Could not create group spot. Please retry.'});
  }
};
