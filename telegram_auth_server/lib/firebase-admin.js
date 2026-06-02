const admin = require('firebase-admin');

function serviceAccountFromEnvironment() {
  const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

  if (!rawJson) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not set.');
  }

  const serviceAccount = JSON.parse(rawJson);

  if (serviceAccount.private_key) {
    serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
  }

  return serviceAccount;
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccountFromEnvironment()),
  });
}

module.exports = {
  admin,
  db: admin.firestore(),
};
