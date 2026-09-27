// Standard Firebase email/password registration. No administrative credentials,
// staff permissions, privileged login path or preaccepted community terms.
const fs = require('node:fs');
const path = require('node:path');
const {randomBytes} = require('node:crypto');
const options = fs.readFileSync(path.resolve(__dirname, '../../lib/firebase_options.dart'), 'utf8');
const apiKey = options.match(/static const FirebaseOptions web[\s\S]*?apiKey: '([^']+)'/)?.[1];

async function request(action, body) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${action}?key=${apiKey}`, {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message || `Auth HTTP ${response.status}`);
  return data;
}
async function main() {
  const destination = process.argv[2];
  if (!apiKey || !destination?.startsWith('/private/tmp/')) throw new Error('Supply a private /private/tmp/ credentials file');
  let credentials;
  if (fs.existsSync(destination)) {
    credentials = JSON.parse(fs.readFileSync(destination, 'utf8'));
  } else {
    credentials = {email: 'communitycarspots+appreview@proton.me', password: randomBytes(24).toString('base64url'), state: 'creating'};
    fs.writeFileSync(destination, JSON.stringify(credentials, null, 2), {mode: 0o600, flag: 'wx'});
  }
  const payload = {email: credentials.email, password: credentials.password, returnSecureToken: true};
  let session;
  try { session = await request('signInWithPassword', payload); }
  catch (error) {
    if (credentials.state !== 'creating' || !/INVALID_LOGIN_CREDENTIALS|EMAIL_NOT_FOUND/.test(error.message)) throw error;
    session = await request('signUp', payload);
  }
  credentials.uid = session.localId;
  credentials.state = 'auth-created';
  fs.writeFileSync(destination, JSON.stringify(credentials, null, 2), {mode: 0o600});
  await request('update', {idToken: session.idToken, displayName: 'Apple Review', returnSecureToken: false});
  const verified = await request('signInWithPassword', payload);
  if (verified.localId !== credentials.uid) throw new Error('Unexpected account ID');
  credentials.state = 'password-sign-in-verified';
  fs.writeFileSync(destination, JSON.stringify(credentials, null, 2), {mode: 0o600});
  console.log('App Review account created and password sign-in verified. Credentials saved privately. Profile onboarding still requires the new app build.');
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
