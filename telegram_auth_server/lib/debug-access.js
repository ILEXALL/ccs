const {admin, db} = require('./firebase-admin');

async function debugAccessStatus(req) {
  const header = req.headers?.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return 401;
  let token;
  try { token = await admin.auth().verifyIdToken(header.slice(7), true); }
  catch (_) { return 401; }
  if (!token?.uid) return 401;
  const user = (await db.collection('users').doc(token.uid).get()).data();
  return user?.role === 'admin' && user.banned !== true && user.deleted !== true ? 200 : 403;
}
module.exports = {debugAccessStatus};
