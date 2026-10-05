const {admin, db} = require('../lib/firebase-admin');
const {createSpot} = require('../lib/create-spot');
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({error: 'Method not allowed'});
  const authorization = req.headers.authorization || '';
  if (!authorization.startsWith('Bearer ')) return res.status(401).json({error: 'Sign in required'});
  let token;
  try { token = await admin.auth().verifyIdToken(authorization.slice(7), true); }
  catch { return res.status(401).json({error: 'Sign in required'}); }
  try {
    const result = await createSpot(db, admin, token.uid, req.body, process.env.R2_PUBLIC_BASE_URL);
    return res.status(200).json({ok: true, ...result});
  } catch (error) {
    return res.status(error.status || 500).json({error: error.status ? error.message : 'Could not create spot'});
  }
};
