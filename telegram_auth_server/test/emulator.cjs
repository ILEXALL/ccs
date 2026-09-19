const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const cli = path.join(process.env.APPDATA || '', 'npm/node_modules/firebase-tools/lib/bin/firebase.js');
const env = { ...process.env, GCLOUD_PROJECT: 'demo-ccs-tests',
  GOOGLE_CLOUD_PROJECT: 'demo-ccs-tests', FIREBASE_CLI_DISABLE_MOTD: 'true' };
delete env.GOOGLE_APPLICATION_CREDENTIALS;
delete env.FIREBASE_SERVICE_ACCOUNT_JSON;
delete env.FIREBASE_CONFIG;
const java = 'C:\\Program Files\\Android\\Android Studio\\jbr';
const pathKey = Object.keys(env).find((key) => key.toLowerCase() === 'path') || 'PATH';
env[pathKey] = `${path.dirname(process.execPath)}${path.delimiter}${env[pathKey] || ''}`;
if (!env.JAVA_HOME && fs.existsSync(path.join(java, 'bin/java.exe'))) {
  env.JAVA_HOME = java;
  env[pathKey] = `${path.join(java, 'bin')}${path.delimiter}${env[pathKey]}`;
}
if (!fs.existsSync(cli)) {
  console.error('Firebase CLI missing. Install firebase-tools with npm.');
  process.exit(2);
}
const result = spawnSync(process.execPath, [cli, 'emulators:exec', '--only', 'firestore',
  '--project', 'demo-ccs-tests', '--config', 'firebase.test.json',
  'node --test --test-isolation=none telegram_auth_server/test/emulator.test.js'],
  { cwd: root, env, stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
