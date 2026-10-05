# Security rollout — compatibility deployment live

The owner authorized the compatibility deployment while preserving older public
builds. Both main and legacy APIs and the additive rules are now live.
Strict rules, authenticated-only uploads, and the private-data migration remain
unapplied. Do not publish the strict `firestore.rules` alone.

## Compatibility deployment record — 5 October 2026

- Main live URL: `https://ccs-wine.vercel.app`.
- Ready deployment: `dpl_B7a7mJammCrhpFFvrS9AkEHmhWWn`,
  `https://ccs-nt4ocrftx-ccs-projects1.vercel.app`.
- Main rollback: `dpl_HLhaa87Ay6HxDASvDXoW1e8aACTo`,
  `https://ccs-ev1xu2qn4-ccs-projects1.vercel.app`.
- Reconstructed and SHA-1 verified all 79 baseline production source files.
  Changed only the community router, notification token readers, and route config;
  added the create-spot handler, creation library, and private-profile helper.
  The production upload handler, authentication handlers, deletion worker,
  scheduler configuration, and all other runtime files were retained byte-for-byte.
- The isolated deployment source is in
  `.dart_tool/security-audit/compat-deploy/` (not the complete current checkout).
  Do not redeploy the entire local server as the compatibility release: the local
  upload handler contains final authentication restrictions.
- The first CLI attempt was blocked by its inherited parent-checkout Git author.
  The successful deployment used the authenticated owner's source-file API with
  the verified baseline and patch, without claiming to deploy that Git commit.
- Active compatibility ruleset:
  `projects/ccsv1-63537/rulesets/b140d733-e16f-4285-ab0b-8a1da125e5a3`,
  released `2026-10-05T19:08:48.259903Z` (22:08 Europe/Kyiv).
  Its exact source is `firestore.compat.rules`; `firebase.compat.json` selects it.
- Previous ruleset for rollback:
  `projects/ccsv1-63537/rulesets/ec843f37-0a11-4927-a5b4-1a27c7ce90c5`.
- The additive rules only permit `users/{uid}/private/account` for its owner and
  allow new public profiles to omit email. Old profile/token writes and direct
  spot creation remain allowed. No production records were migrated.
- Three additional emulator tests pass for legacy/new profile writes, legacy
  spot creation, private-document isolation and unchanged consent behavior.
- Staged and live empty-request checks pass: create-spot, XP, deletion and both
  notification routes reject missing app authentication with 401. The legacy
  upload route retains its existing 400 response to a missing path. Shared
  routes identify this release with `X-CCS-Compatibility-Version: 1.1.0-stage1`.
- The legacy host belongs to `gamezone047@gmail.com`, team
  `eugene-rachevsky-s-projects`, project `ccs-telegram-auth-server`. Browser access
  is confirmed, and its notification compatibility patch is live.
- Legacy live deployment: `dpl_D913BF2kKLGHrQhVp81EpfbUGqFf`,
  `https://ccs-telegram-auth-server-ihz65jpkx-eugene-rachevsky-s-projects.vercel.app`.
  Live alias: `https://ccs-telegram-auth-server.vercel.app`.
- Legacy rollback: `dpl_9J5vKkRx4FwV3GSZLmHS8nYQuJ8A`,
  `https://ccs-telegram-auth-server-86fny1gvn-eugene-rachevsky-s-projects.vercel.app`.
- Reconstructed and SHA-1 verified all 98 legacy source files. Changed only
  the two notification handlers and added the private-profile helper; all other
  files were preserved. Isolated source: `.dart_tool/security-audit/legacy-deploy/`.
- Legacy existing tests: 76 passed. Notification dispatch tests against actual
  staged main and legacy handlers: 10 passed. Staged and public legacy checks
  return application 401 for both notification routes and unchanged upload 400
  for a missing path. Final aliases and the active ruleset were re-read and verified.
- Real-device 1.1.0 sign-in, upload, eight-group spot creation and notification
  delivery between old/new clients still need acceptance testing. No APK built.
  Anonymous uploads and historical public private fields remain until the strict
  cutover; this compatibility release does not resolve those production exposures.

## Pre-deployment production audit

Read the actual Firebase Rules release using the authenticated Firebase CLI
libraries (read-only). The console's rules-version error no longer prevents
verification. This did not repair the console UI itself.

- Project: `ccsv1-63537`, default database.
- Release: `projects/ccsv1-63537/releases/cloud.firestore`.
- Ruleset: `ec843f37-0a11-4927-a5b4-1a27c7ce90c5`.
- Updated: `2026-09-28T12:25:58.777151Z`.
- Active rules allow signed-in reads of public user documents, including legacy
  email/token fields, and direct spot creation without consent enforcement.
- The earlier probes of both production photo endpoints returned unsigned-user
  upload capabilities. No photo was uploaded by those probes.
- Local audit copies are in `.dart_tool/security-audit/` (ignored by Git).

## Implemented locally

- Email and push-token writes move to `users/{uid}/private/account`. Only the
  owner can read/write this document; the public-profile model ignores email.
- Final rules reject private fields in public user documents, including staff
  writes. Existing stored fields must still be migrated: a write restriction
  alone does not hide historical data.
- Both notification handlers read the private token document and support old
  public tokens during transition. Invalid-token cleanup does not recreate
  public fields after migration.
- A dry-run-by-default migration atomically copies private fields and removes
  them from each public profile, preserves existing private data and both token
  sources, and can be rerun. Output contains counts only.
- Upload signing verifies Firebase authentication/revocation, deletion state,
  account bans, supported image types, strict object paths and ownership.
  Nonexistent shared `spots/` prefixes cannot be claimed. New spot photos already
  use the uploader's `users/{uid}/spot_photos/` prefix. Pre-profile avatar upload
  remains available to authenticated users.
- `/api/create-spot` shares the existing Vercel community function (no extra
  function slot). Creation checks current consent, account/deletion state,
  regional restrictions and membership in up to eight groups in a transaction.
  Author/status/counters/group metadata are server-derived. Spot, group links
  and event topic commit together. Repeating the same ID/payload is idempotent.
- Flutter uses the new creation endpoint. Final rules reject direct spot
  creation, including by staff, preventing a consent bypass.
- Private documents remain inside the existing recursive account-deletion tree.

## Compatibility constraint and rollout

Older builds write private fields to the shared profile and create spots
directly. Historical build 13 sends no bearer token when requesting uploads.
There is no secure way to accept those anonymous upload requests while also
requiring authentication. Re-enabling public writes would reopen the privacy
issue. No such exception was added to the fixes.

Before final activation:

1. Inventory which public builds are still supported and which upload hostname
   they use. Reconfirm the active ruleset before any publication; do not overwrite
   intervening production changes with the saved snapshot.
2. Prepare an additive compatibility rules release from the then-active rules:
   allow the owner-only private document and allow a new public profile without
   an email field, while leaving legacy public writes intact temporarily.
   Deploy/test the new spot endpoint and notification readers without silently
   changing legacy upload behavior. This transitional stage is NOT a complete
   privacy fix.
3. Test an updated app against that staging configuration: Google/Apple/Telegram
   sign-in, new profile, consent, avatar/garage/spot/chat uploads, eight-group
   creation, notifications, and deletion. A physical-device test of these new
   changes is still outstanding. The user builds the app; no APK was built here.
4. Agree on retiring incompatible legacy writes/uploads. Until then the public
   exposure remains an open App Store readiness blocker. Do not claim it fixed.
5. Coordinate the strict rules, authenticated upload handlers on BOTH hosts,
   and the private-field migration. During cutover, temporarily gate writes so
   an old client cannot recreate private fields while migration runs. Migrating
   before restricting legacy writers is insufficient; restricting first can
   temporarily reject updated profile writes until each old record is moved.
6. Dry-run the migration with the server's existing secret environment:
   `node scripts/migrate-private-profiles.cjs --project ccsv1-63537` from the
   server directory. Do not copy credentials into command arguments or Git.
   After legacy writers are retired, apply with `--apply --legacy-writers-retired`.
   Rerun dry-run and require `affected: 0`.
7. Verify the released ruleset through the Rules API and rerun production
   negative-access checks with disposable accounts. Anonymous upload requests
   must return 401 on both hosts; another account cannot read private documents;
   direct spot creation must fail; authenticated server creation with recorded
   consent must succeed. Verify notification delivery and deletion again.

## Validation completed

- 114 offline server tests (including actual upload-handler authentication tests).
- 13 existing Firestore rules emulator tests, updated for server-only creation.
- 8 new migration/access/creation emulator tests, including concurrent retries,
  eight-group atomic writes, staff-country checks and new-profile onboarding.
- 21 deletion emulator tests, including removal of the new private document.
- 6 Flutter Terms/consent tests.
- Targeted Dart analysis: no errors or warnings (two pre-existing style infos).
- No production account contents modified, no real uploads or pushes sent.

The migration and complete production security cutover remain unapplied because
the owner chose to keep older public builds working.
