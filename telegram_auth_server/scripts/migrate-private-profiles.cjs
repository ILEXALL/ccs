// Run with the server's existing FIREBASE_SERVICE_ACCOUNT_JSON, never paste keys.
// Dry run: node scripts/migrate-private-profiles.cjs --project ccsv1-63537
// Apply only after retiring legacy writers and activating the strict rules:
// add --apply --legacy-writers-retired
const {migratePrivateProfile} = require('../lib/private-profile');
async function main() {
  const args = process.argv.slice(2);
  const project = args[args.indexOf('--project') + 1];
  if (!args.includes('--project') || project !== 'ccsv1-63537') throw new Error('Explicit CCS project required');
  const apply = args.includes('--apply');
  if (apply && !args.includes('--legacy-writers-retired')) throw new Error('Retire old public-profile writers before applying');
  const account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON || '{}');
  if (account.project_id !== project) throw new Error('Credential project does not match');
  const {db, admin} = require('../lib/firebase-admin');
  let cursor, scanned = 0, affected = 0;
  for (;;) {
    let query = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(100);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const user of page.docs) {
      scanned++;
      if (await migratePrivateProfile(db, admin, user.ref, apply)) affected++;
    }
    cursor = page.docs.at(-1);
  }
  // No PII, tokens, credentials, or document contents in output.
  console.log(JSON.stringify({project, mode:apply?'apply':'dry-run', scanned, affected}));
}
main().catch(error => {console.error(error.message);process.exitCode=1;});
