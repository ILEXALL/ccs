# CCS App Store release — 25 September 2026

## October 4 optional free globe prototype

October 5 UI refinement: the globe is embedded within the existing Map tab,
keeping the real app navigation visible and Map selected. Share live is at the
top right, style/filter/alert controls at bottom left, and globe/follow at right.
Controls have 36px visual surfaces and at least 48px tap targets. The old map
remains mounted for the existing session/controllers; globe data updates pause
when another tab is selected. Three native-widget layout/interaction tests cover
portrait, landscape, sharing callbacks and preview cards with navigation visible.
Physical-device verification is still needed; no APK was built.

Map screen now offers **Try globe** on Android/iOS. This is an optional preview,
not a replacement for the production map: MapLibre GL JS 5.6.2 is bundled with
its license and rendered by the official Flutter WebView plugin. OpenFreeMap
provides Positron (light) and Dark vector basemaps; attribution remains visible. No account/key,
Firebase schema migration, backend deployment or new database subscription.
Existing filtered spots, permitted live locations and current GPS are passed
locally as GeoJSON once per second when changed. Tapping a spot/person opens
the existing card over the globe without popping the route. Follow mode, globe
overview, live-sharing toggle, filters and add-alert controls are provided.
Sharing retains its existing state; opening the preview never enables sharing.
The self marker reuses the standard navigation-arrow painter and current heading.
Style switches restore icons/data and preserve the camera. Both category artwork
variants are bundled locally. Active alerts and their existing cards are available.

The globe reuses the standard map's category PNG artwork, category colors,
event/closed styling and 11.25 zoom threshold between dots and full icons.
All eligible filtered spots are retained without clustering or icon collision hiding.
Artwork is resized to 128px at runtime before transfer to the local WebView.
People counters and XP rings still require migration from the standard map.
It requires a new mobile build; no APK/IPA was built here. Desktop browser globe
rendering/attribution and light/dark switching verified, five renderer tests and
five spot style/visibility tests pass. Dart analysis has no errors/warnings (map-screen style
infos remain). Native WebView asset loading, gestures, background/resume, live
tracking, battery/memory and iPhone/iPad performance still require device tests
before including this feature in the App Store release. Recheck privacy
disclosures for the map provider; do not describe this prototype as release-ready.

## October 4 public deletion rollout

User approved public activation and explicitly approved read-only production
verification using existing Firebase/R2 credentials with absence/count results
in private Vercel logs. Diagnostic `dpl_B89egvP3TZLkEv9wYcnjNTupPQoQ`
verified `hoedeadlov`: Auth absent; profile, username, XP stats, live location and
presence absent; no profile child collections or deletion work rows; sampled
indexed ownership queries empty; both users/ and garage/ R2 prefixes empty with
no truncation; legacy Firebase Storage bucket absent (404). This checks those
paths, not every possible historical schema. Diagnostic deliberately exited 1
after printing its result to prevent publishing any endpoint or changing aliases.

The iOS request completed October 3 at 20:15:04 Kyiv, 3h 3m 2s after its
17:12:01 request. This single-account measurement is not a guaranteed maximum
under concurrent load. Twenty-five offline deletion/security/storage tests pass.
Public activation is deployed as `dpl_HLhaa87Ay6HxDASvDXoW1e8aACTo`
(`ccs-ev1xu2qn4-ccs-projects1.vercel.app`) on `ccs-wine.vercel.app`.
`ACCOUNT_DELETION_ENABLED=true`; the retained test UID is ignored in public mode.
The shared `round-robin` worker completed its normal October 4 23:00 Kyiv run:
`lastRunOk=true`, `attempted=0`, `pending=false`, lease released. Unauthenticated
deletion and XP probes both return 401. No user accounts were submitted by these
checks. Five-minute Cloudflare scheduling continues, and Vercel's daily backup
at 03:00 UTC is configured; its first actual daily execution remains unverified.
No app rebuild or Firestore rules change is required for this activation.

## October 3 deletion investigation (historical)

Public rollout requested by user October 3 after successful iOS submission.
Pre-activation inspection at approximately 17:36 Kyiv found `hoedeadlov` still
`processing`: requested 17:12:01, latest progress 17:35:24, 1,910 documents
processed. Scheduled calls at 17:20, 17:25, 17:30 and 17:35 all returned HTTP 200.
Public deletion was NOT enabled: successful request acceptance is not complete
cleanup verification. Keep the worker running for this accepted request; verify
completion and independent Auth/Firestore/media absence before public activation.
The user's public-rollout authorization is recorded; no repeated permission
question is needed for that rollout once its verification gates pass.

- Corrected iOS tester username: `hoedeadlov`. No deletion job exists for
  this account at inspection time. The reported generic connection message
  does not establish the underlying iOS failure; device build/timing remain unknown.
- Public deletion is still disabled. After the old job completed, the user
  explicitly authorized `hoedeadlov` as the sole allowed test account. Do not
  treat Apple deletion as verified or enable public deletion yet.
- Earlier disposable account `pro100_bro2` now has job status `complete`,
  completed October 2 at 03:25:04 Kyiv, about 3 hours 3 minutes after request.
  This is a job-state observation, not an independent full data/R2 audit or SLA.
- The XP rollout lost a deployment-only test UID, causing scheduler HTTP 503.
  Restored the original UID as a production project environment variable and
  redeployed, then switched to the approved iOS test account in deployment
  `dpl_CaQTZarBLsctccNgMRu8GuZ8hPun` on `ccs-wine.vercel.app`.
  Also restored the previously audited storage bucket and allow-missing settings
  as production project variables after their omission caused HTTP 500.
  The normal 16:45 Kyiv scheduler run succeeded: `lastRunOk=true`, `attempted=0`,
  `pending=false`. No test deletion had been requested yet.
- Local deletion errors now distinguish network, timeout, malformed response,
  Firebase confirmation/revocation and known server rejection failures without
  exposing raw exception messages. Cancellation handling includes additional
  cancellation codes. All 23 focused Apple/deletion tests pass; targeted analysis
  is clean. These changes require a new mobile build and real iOS testing.

Historical setup notes below are chronological and may have been superseded.

October 3 console update: saved and re-opened Apple App ID G6BV2G5633
(`lv.ilexall.ccs`, team N7BDW56D69); Sign In with Apple is checked, enabled as
primary App ID. Push Notifications remains enabled. Apple warned that profiles
using this App ID must be regenerated for future builds. Firebase Apple provider was saved after explicit approval. The provider table verifies Apple Enabled alongside unchanged Google, Email/Password and Anonymous Enabled. No user accounts were migrated or merged. Services ID/code-flow fields
remain blank; credential configuration and real-device validation remain pending.

October 3 Services ID update: registered `lv.ilexall.ccs.auth` (CCS Firebase
Authentication), then saved its Sign in with Apple configuration after explicit
approval. Primary App ID is `N7BDW56D69.lv.ilexall.ccs`; domain is
`ccsv1-63537.firebaseapp.com`, return URL is
`https://ccsv1-63537.firebaseapp.com/__/auth/handler`.
Prepared a new key named CCS Firebase Apple Sign In with only Sign in with Apple
enabled for the primary App ID. User completed registration; Key ID is
`8LPHNLCCP3`. Clicked Download at user request; Apple shows Downloaded, but the
browser download event timed out without returning a saved path. No matching file
was found in the user's standard Downloads directory. Confirm the file's local
save location with the user before proceeding. Firebase private-key entry is
still pending; no key contents were read or printed.
Existing APNs key V92Q9VF4PM (CCS Firebase Push) was not modified.
## Sign in with Apple implementation — 2 October 2026

Local implementation added; not released or verified on Apple hardware:

- iOS login uses Firebase's native Apple provider (nonce/exchange handled by the
  installed SDK), then existing nickname/profile/consent routing. Relay email is
  not suggested as a public nickname. Failed profile setup signs out.
- Settings offers explicit consent to link Apple to the currently authenticated
  Firebase UID, including existing Google/Telegram accounts. No custom email
  matching or automatic merging. Credential collisions preserve the session and
  explain the conflict. Existing Telegram username metadata is preserved.
- Login layout scrolls on small screens; Apple entitlement added to Runner.
- Confirmed deletion reauthenticates Apple-linked users and revokes Apple access
  before queuing deletion; missing codes and revocation failures stop submission.
  Non-Apple accounts and already-accepted receipt recovery keep their old flow.
- Seven authentication unit tests pass; eight existing deletion/consent tests
  pass; one small-iPhone layout test passes. Targeted Dart analysis is clean.
  These tests mock authentication; they do not verify Apple's real OAuth service.

Firebase console was inspected: Apple provider is NOT configured. The Apple
Developer identifiers tab is open at sign-in, awaiting the user's login. No live
provider, capability, rules, backend, or scheduler settings were changed.

Remaining setup/validation: enable Sign in with Apple for `lv.ilexall.ccs` in the
Apple Developer account, configure Firebase Apple provider/code flow credentials
as required for revocation, refresh iOS provisioning, and test on iPhone/iPad.
Test new signup (including Hide My Email), returning login, cancelled sheet,
existing Google and Telegram linking with unchanged UID/data, collision handling,
and account deletion/revocation. Verify deletion of an Apple-linked account from
Android too: native Apple authorization-code retrieval has only been implemented
and documented for Apple platforms; cross-platform OAuth/revocation configuration
remains a release blocker. Never claim end-to-end Apple readiness from unit tests.

References: https://firebase.google.com/docs/auth/flutter/federated-auth#apple
and https://developer.apple.com/app-store/review/guidelines/#login-services.

## Latest verified account-deletion status — 1 October 2026

October 2 follow-up: the user rebuilt/installed the Android app and confirmed the
status/Dismiss fix works. They authorized a fresh scheduler-only deletion test.
New disposable account: `pro100_bro2`, UID `MLlXb8PO8Yfkx2rcS6g7g6kL7mE2`.
Read-only baseline at 00:16:25 Kyiv: Auth enabled, profile present, one legal
acceptance, one R2 users-prefix file and one garage-prefix file, no deletion job.
Canonical deployment is now dpl_BNmyEUBDMEpqzcHhP9sgAs9HX5aS,
https://ccs-naufkvwph-ccs-projects1.vercel.app, with public deletion false and only
this test UID enabled. Cloudflare ENABLED=true / VERIFY_ONLY=false was verified
around 00:19 Kyiv. Its normal cron succeeded at 00:20:14 Kyiv (lastRunOk=true,
lastFinishedAt=1790889614763); an independent read at 00:20:59 confirmed fresh
health and no deletion request yet. The user can now sign out/in and delete the
test account. No manual worker invocation in this test.
The user confirmed the in-app deletion request. Read-only diagnostic at 00:22:54
Kyiv confirmed jobStatus=queued, requestedAt=1790889726045 (00:22:06 Kyiv), with
lastRunOk=true from the 00:20 cron. No manual worker calls were made. The six-minute
cooldown ends at 00:28:06; the first eligible scheduled batch should be around
00:30 Kyiv. Completion time and post-deletion data/media absence remain unverified.
The diagnostic build ccs-mqvqign76-ccs-projects1.vercel.app was not promoted;
its expected missing-public-output error occurs after the read-only diagnostic.
Scheduler-only progress check at 00:36:08 Kyiv: job processing,
documentsProcessed=975, lastProgressAt=1790890536520 (00:35:36), scheduler
lastRunOk=true and lastFinishedAt=1790890537070 (00:35:37). This confirms automatic
progress after approximately 14 minutes since request, not a stalled UI.
975 is the worker's documents-processed counter, not a count of this user's
records deleted or a completion percentage. Remaining full-database traversal
still needs timing/performance evaluation; no completion estimate established.
Read-only diagnostic: ccs-6cbdl53kj-ccs-projects1.vercel.app (not promoted).
October 2, 01:07 Kyiv: normal cron still progresses, lastRunOk=true at 01:05:37,
documentsProcessed=4060. Read-only verification found currentRoot=xp_transactions,
with many other roots still pending. Auth is disabled but exists; profile and both
R2 files still exist, so this is NOT complete. No worker invocation or production
code change was made during the timing test.

Prepared LOCAL scan optimization (not deployed): collection pages 25 -> 100 and
transaction groups 10 -> 25. Pending-path persistence preserves mid-page resume.
Added a 130-document integration case with interrupted pages, orphan descendants
and other-user preservation. All 21 emulator integration/rules tests and 25 offline
account tests pass. Sequential local benchmark, mocked Auth/storage, 2,000 unrelated
+ 50 owned messages: baseline 9,667ms / 84 pages; candidate 3,679ms / 22 pages.
Both take three invocations due the unchanged 1,000-document cap; emulator speed
must not be treated as production deletion latency. Baseline implementation saved
in the local Temp ccs-deletion-benchmark-baseline-20261002 directory; benchmark now
accepts CCS_DELETION_BENCHMARK_IMPLEMENTATION for reproducible comparisons.
Do not replace the deployed baseline during this scheduler-only timing test.
The remaining full scan (including XP history) still requires relationship-index
coverage/audit before public activation; batching alone does not solve scaling.
The previous deployment/disabled state described below is historical. Receipt
and tombstone expiry need a separate check because restricted test mode skips
global metadata purging. Public activation is not yet authorized by verification.

The real disposable account `pro100_bro` completed deletion at 23:37:50 Kyiv.
Independent checks confirm Firebase Auth and profile absence, no profile
subcollections, username reservation removed, no owned XP transactions,
push-delivery records or user notifications, both R2 user/garage prefixes empty,
and all worker subcollections empty. The anonymous receipt reports `complete`.
At 23:40:36 Kyiv the exact test queue marker and hashed test scheduler state were
also removed and verified absent, after over 65 minutes had elapsed since Auth
was observed disabled. The anonymous completion receipt was preserved. This
manual test cleanup does not establish ordinary scheduled metadata expiry.
This was an assisted diagnostic run with deployments and extra worker invocations;
its 65m40s request-to-completion duration is NOT a normal-operation SLA.

Current live deployment: dpl_4Bkm6ZwuA8X3QCcWyFasopmbogrW,
ccs-eoucfpwo4-ccs-projects1.vercel.app, assigned to ccs-wine.vercel.app.
Public deletion is disabled, the temporary test UID override is empty, and a new
request probe returns 503. Cloudflare ENABLED=false and VERIFY_ONLY=false.
The latest fixes are deployed, but they have NOT been enabled for public use.
No APK was built and no Firestore rules were deployed in this verification step.

Validated changes: batched atomic scanning, fair use of available worker time,
indexed cleanup of the two dominant history collections, copied chat/spot/topic
notification cleanup, and bulk removal of temporary deferred checks when no
source content was deleted. 25 offline tests, 20 emulator integration/rules tests,
and two status-refresh widget tests pass; targeted Dart analysis is clean.
The client now visibly confirms refresh activity; this needs the user's next build.

Before public activation: audit remaining legacy notification/media schemas and
all writers that could recreate deleted content, reduce/measure remaining scans
under ordinary scheduled operation and backlog, verify receipt/marker expiry,
and only then publish deletion timelines in the app and public documents.
Existing release notes below are chronological history, not all current state.

October 2 status-button diagnosis: the installed build kept showing processing
after successful HTTP 200 status requests. A read-only receipt check found exactly
one receipt, complete at the verified test timestamp; no processing receipts.
The old client used `setState(() => status = accountDeletionStatus())`, returning
a Future from the callback. Flutter's debug assertion throws before markNeedsBuild,
leaving the previous FutureBuilder result visible. The already-updated local
widget uses a synchronous block callback and passes refresh/completion/error tests
and Dart analysis. The user must rebuild/install to get the permanent client fix.
Force-closing/reopening the existing app recreates the initial status query and
can display completion without using the faulty refresh callback. Preserve app
data/the receipt; no further Vercel or rules deployment is needed for this UI fix.

## Current release

App Store Connect app 6778200005, version 1.0.9, uploaded build 13. Not submitted.
Free, all available countries selected; manual release. Metadata, reviewer contact,
five iPhone screenshots and five iPad screenshots were saved in earlier work.
Age questionnaire saved (13+ in most regions). Recheck current console state before submission.

Support: https://sites.google.com/view/community-car-spots

Published privacy policy: https://sites.google.com/view/community-car-spots/privacy-policy

Support/reviewer email: communitycarspots@proton.me

## Local changes, not deployed

- Added bundled Terms of Use and links from login and settings.
- Added an agreement screen before community access, including returning accounts.
- Consent is saved under `users/{uid}/legal_acceptances/2026-09-24` with a server timestamp.
- Client consent records are private to the account and immutable. Retry uses a transaction
  to retain the original timestamp when the first write succeeded but its response was lost.
- This is a client navigation gate, not a backend requirement on all content writes.
- Existing uploads still need an independent rights review; new agreement is not retroactive.
- Terms page published and publicly verified on 24 September 2026:
  https://sites.google.com/view/community-car-spots/terms-of-use
  Source: `assets/legal/terms.txt`.

Validation on 25 September: 84 offline server tests, 20 Firebase Emulator integration/rules
checks (including upload-expiry protection) and 8 Flutter widget tests passed. Targeted
Flutter analysis found no issues; an iOS simulator debug build completed successfully
(`build/ios/iphonesimulator/Runner.app`). This is not a signed App Store archive. Production rules have NOT been deployed.

### Account deletion and review access (local implementation)

- Added Settings → Delete account, recent sign-in check, explicit irreversible confirmation,
  and private status receipt on the sign-in screen. Receipts are bound to the initiating UID.
- Added a resumable backend queue, token revocation, disabled account, private queue rules,
  R2 prefix cleanup and content/reference cleanup. Completion is recorded only after cleanup.
- Account requests remain disabled unless `ACCOUNT_DELETION_ENABLED=true`, `CRON_SECRET`
  and the R2 configuration are supplied. Do not enable yet: staging and production storage
  verification, throughput assessment and the remaining release issues below are pending.
- Queued accounts cannot use old tokens under the new rules. Backend token verification
  checks revocation. Upload signing now requires authenticated ownership.
- Added email/password sign-in through the normal account/profile/consent flow.
- Created `communitycarspots+appreview@proton.me` in Firebase Authentication and verified
  password sign-in using the documented Firebase REST API. No reviewer bypass or admin role.
  Credentials are stored privately outside the repository, not in App Store Connect yet.
  New-app profile onboarding and end-to-end review access still need verification.

### Free hosting and deployment readiness

User requires free hosting: no Pro upgrade, trial, paid add-on or purchase is authorized.
Account deletion shares `api/community.js`; there are still 12 files in `api/`.
The one daily cron is `0 3 * * *`; the function maxDuration is 60 seconds, worker budget
35 seconds per invocation, at most 5 accounts and 250 processed documents per account.
The listing page size is 25. These are work limits, not a guarantee that the entire app
will stay below Vercel/Firebase/R2 quotas. Measure actual usage before enabling.

The initial deletion implementation traversed the database twice to find legacy and
copied references. The 27 September local update below replaces the second traversal
with a reply-reference checklist; one full traversal remains. For a large database or
backlog this can still take many daily runs. Before enabling, replace that traversal
with an indexed ownership inventory where necessary, verify backlog fairness,
and establish a tested completion timeframe for the UI/privacy notice. Do not promise
instant deletion or a 24-hour completion time. No production deletion was performed.

### Corrected hosting investigation — 25 September

The prior conclusion that `ccs` was the wrong backend was incorrect. `docs/WEEKLY-REWARDS.md`
records the migration on 21 September. Verified via the Vercel API: `ccs`, project
`prj_0JHXarM8RMHLWpAvXkjHbUK20hoa`, team `team_oBfxCLsNMQCxeuuOgjgtCT2O` / `ccs-projects1`,
GitHub `ILEXALL/ccs`, root `telegram_auth_server`, production alias `ccs-wine.vercel.app`.
Production deployment at investigation: `dpl_AjVg8wXxE98tgAwhfh7Ek4uzVeRX`.
The old `.vercel` binding is stale. Do not deploy using that binding.

Both hosts respond. The current host exposes `weekly-live-v1`; old host lacks that marker.
Account deletion is 404 on both. The new deletion client now uses the canonical base URL.
Other legacy routes (R2, moderation, groups, push, usage) still point at the old server:
do not switch them until their runtime configuration and authenticated behavior are verified.

Firebase/Telegram variables in `ccs` have type `sensitive`. Their empty exported values DO
NOT mean that production values are missing: Vercel intentionally does not disclose them.
Do not overwrite them with the empty export. No need to obtain those credentials locally
for a normal remote deployment. R2 variable names are absent from the current project's
listed environment, and R2 access is still required to enable deletion safely.
Reference: https://vercel.com/docs/environment-variables/sensitive-environment-variables

Safari authentication settings confirm GitHub ILEXALL and Google pasegorov@gmail.com are
linked to the same Vercel account. Only ccs-projects1 appears, with no pending invitations.
No need to ask the user or their collaborator to rediscover the current backend.
Visible team is Hobby. Last-30-day usage: 6.6K / 1M function invocations, about 29m / 4h
active CPU, 3.7 / 360 GB-hours memory, 3.36 / 10 GB function storage.

Official hosting references checked 25 September:
- https://vercel.com/docs/cron-jobs/usage-and-pricing — Hobby cron at most daily.
- https://vercel.com/docs/plans/hobby — included usage; Hobby is personal/non-commercial.
  Reassess hosting before introducing the paid partner promotion discussed by the user.

Deployment must be coordinated with clients: build 13 does not send an upload auth token,
so deploying the new upload endpoint first would break photo uploads for that build.
Do not weaken authentication to accommodate it. Prepare and test the replacement client,
then choose an explicit rollout/minimum-version policy before production deployment.

Deploy and verify the consent rules before distributing a build containing the new gate.
Without those rules, consent saving fails and users cannot enter the community.
The uploaded build 13 does not contain these changes; prepare a new build number after
all release fixes are complete.

## Outstanding release work

1. DONE: Safari interaction restored after the user unlocked the Mac.
2. DONE: Approved Terms of Use published on Google Sites; public navigation, URL and text verified.
3. DONE: App Privacy verified in the live console on 24 September: published yesterday
   by Aleksej Pasegorov. All fourteen configured types and the privacy URL are present.
   Earlier local notes incorrectly listed publication as pending; live state takes precedence.
4. Review rights to existing user content and map tiles/data. Content Rights in App Store
   Connect remains intentionally unset; user asked to leave it pending verification.
5. Complete deployment/readiness work for the local deletion implementation above. Public
   privacy/terms currently describe email support; update only after the new flow is verified.
6. Resolve Apple sign-in requirements for the current Google/Telegram authentication flow.
7. Verify content filtering, reporting, blocking and moderation against review requirements.
   User confirmed manual moderation and bans, with no automatic chat filtering.
8. Test the prepared review account in the new iOS build, complete normal onboarding, then
   save its credentials and instructions in App Store Connect. Reviewer fields remain empty.
9. Review any outstanding Apple Developer agreement with the account holder before acceptance.
10. Validate rules and release changes, deploy required backend changes, archive/upload the
    replacement build, select it, check export compliance and all console validation,
    then submit for review. Release follows approval because manual release is selected.

No App Store submission, legal acceptance or production rules deployment has been performed.
Public Terms publication is now complete.

## Preview deployment — 25 September 2026

Created an isolated remote preview in the existing Hobby project `ccs`:
https://vercel.com/ccs-projects1/ccs/31CLVDp3MvZD6ca1hax3XUXK6XVR

Endpoint host: https://ccs-kqctv8ypu-ccs-projects1.vercel.app
Sources staged under `/private/tmp/ccs-appstore-preview`, excluding local environment
files, credentials, node_modules, tests and scripts. No production promotion.
Vercel's existing sensitive Firebase/Telegram variables were preserved.

Verified through authenticated Vercel deployment access, with NO Firebase user token:
- POST /api/account-deletion → 503 (feature deliberately disabled).
- POST /api/xp-sync → 401.
- POST /api/r2-presign-upload → 401.
- POST /api/account-deletion with a synthetic nonexistent status receipt → 200 unknown,
  confirming the inherited Firebase configuration works without exporting its secret.
- Vercel API confirmed production deployment ID unchanged.

Complete offline backend suite (all *.test.js/*.test.cjs except emulator.test.js):
167 passed, 0 failed. Corrected deletion URL uses the canonical app base and passes
targeted Flutter analysis. Previous simulator build predates this URL-only correction.

Cloudflare dashboard opened in Safari; user completed sign-in. Inspecting R2 in
account `77cd306e2d923f8e921fcdd0544c2e03` to identify the CCS bucket. No Cloudflare credentials created,
no storage objects changed, no paid plan enabled.

Cloudflare follow-up: user switched to account `78ed1f58c2e8add98e67bfb03364b260`,
display name `Pasegorov8@inbox.lv's Account`. R2 Object Storage redirects to `/r2/plans`
and displays “Get started with R2” / “Add R2 subscription to my account”. R2 is not
activated in this account; no subscription was added. Switch Account lists only this
one account. The earlier Gmail account's actual R2 bucket inventory remains unverified.

## R2 configuration follow-up — 27 September 2026

User requested continuing account deletion setup, deferring repeated code review and
test runs until the release work is assembled. No code review or tests were run in
this follow-up; final end-to-end verification remains required before enabling deletion.

Cloudflare's Gmail account `77cd306e2d923f8e921fcdd0544c2e03` is now accessible.
The existing `ccs` bucket contains approximately 2.02k objects / 395.35 MB, with
`garage/`, `spots/` and `users/` prefixes. Location: Eastern Europe (EEUR).
There are no bucket lock rules. Public development URL:
https://pub-58fc7808870549c1b806ae6aafabcd0d.r2.dev
S3 endpoint: https://77cd306e2d923f8e921fcdd0544c2e03.r2.cloudflarestorage.com
No new R2 subscription is needed to access this existing bucket.

The Cloudflare token list shows an active account token with Object Read & Write
for all buckets and an active user token with Admin Read & Write for all buckets.
Their secret values were not retrieved. The current Vercel `ccs` project still
lists only its four existing Firebase/Telegram/base-URL variables, with no R2 variables.

After user confirmation, created the Cloudflare account token `ccs-vercel-storage`:
Object Read & Write, restricted to bucket `ccs`, Forever lifetime. Saved
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_BUCKET_NAME`,
`R2_PUBLIC_BASE_URL` and `ACCOUNT_DELETION_ENABLED=false` in the Vercel `ccs`
project, Production environment, all with Secret type. Vercel confirmed the save;
these values take effect on a new deployment. No credentials were written to the
repository. Preview does not have these newly added variables.

Local follow-up implementation: the GET worker now also checks the feature flag.
Added a private scheduler lease and persistent round-robin cursor so a large or
failing account cannot occupy the first five daily slots indefinitely. Each job
gets up to a 7-second cooperative work budget within the existing 35-second total;
individual in-flight operations can overrun that budget. Scheduler state is excluded
from account cleanup scans. These edits have NOT been tested, per the user's request.

Remaining before activation: assess the remaining first whole-database traversal
and add a broader ownership inventory if needed for a practical completion time;
validate queue fairness, storage deletion and actual completion times in the final
test phase; deploy rules/backend in coordination with the replacement client.
No storage objects changed, no deployment performed and deletion remains disabled.

Scheduler secret setup completed after the user selected the import file in
Safari. Saved CRON_SECRET with Secret type for Production in the `ccs` project;
Vercel displayed the variable and a successful-save confirmation. Removed the
private temporary import file after saving. No secret value is stored here.
The saved Vercel CLI authorization returned HTTP 403; use the authenticated
browser session or refresh CLI authorization for subsequent deployment work.
The daily schedule is prepared in vercel.json but has NOT been deployed or run.

### Reply reference cleanup follow-up — local, untested

Replaced the second complete database traversal with a private per-job
`reply_checks` list. The first pass records reply document paths; after collection
and media tasks finish, the worker rereads each reply and looks up its current
source in the deleted-message index. It clears quoted fields only if that source
was deleted. A retargeted reply to someone else's message is preserved. Both reply
checks and temporary reference-index cleanup resume within the work budget.
The remaining first traversal still handles legacy ownership and nested references;
this is NOT a complete indexed ownership inventory or a verified deletion SLA.

Added an emulator regression case for deferred reply cleanup across interruptions,
including retargeting a reply before cleanup, and adapted the handler test dependency
stub for the new queue module. Tests were authored but NOT run, as requested.
No deployment or deletion activation was performed.

## Account deletion audit — 1 October 2026

The public build is in use. Do not replace its upload endpoint, change the R2
bucket, deploy the entire pending server/rules migration, or enable deletion
without a compatible rollout and an end-to-end test. Free hosting remains a
user requirement. Apple requirements were checked against:
https://developer.apple.com/support/offering-account-deletion-in-your-app/

Implemented locally in this audit:

- Deleted Firestore containers now propagate deletion to descendants, including
  children below missing intermediate documents. Empty groups are removed;
  groups with remaining members retain those members and transfer ownership.
- Copied spot notifications, reviews and group links are checked against the
  deleted-content reference index after scanning. Existing deferred quote cleanup
  still checks the current source, preserving replies retargeted to other content.
- Encoded Firebase Storage photo URLs are scrubbed, and legacy reviewer UID fields
  are included in reference cleanup.
- Storage cleanup now requires both R2 and Firebase Storage. It enumerates legacy
  Firebase object generations and propagates permission/partial-delete failures.
  New required backend configuration: FIREBASE_STORAGE_BUCKET, expected project
  bucket ccsv1-63537.firebasestorage.app. This has NOT been verified against live
  storage or its soft-delete/retention settings.
- New spot photos use users/{uploaderUid}/spot_photos/{spotId}/... so uploads remain
  attributable even when the spot save fails. Existing spots/{spotId}/ objects
  still need the corresponding ownership records; unknown legacy/orphan ownership
  has NOT been audited. No existing objects were moved or deleted.
- Banned users and users declining updated terms can reach Delete account.
  Notification preference checks refuse missing/deleting recipients and fail
  closed on lookup errors.
- Queue fairness, lease recovery and scheduler health are recorded/tested. New
  requests require a successful worker run within 15 minutes. Completed UID
  tombstones are eligible for cleanup after one hour, anonymous completion
  receipts after 30 days, and idle queue cursors no longer retain a UID.

Validation:

- 18 offline deletion/storage/scheduler tests passed.
- 13 Firestore emulator integration/rules tests passed (demo-ccs-tests only).
- 9 Flutter account/consent widget tests passed; targeted Dart analysis is clean.
- Reproducible benchmark: `node telegram_auth_server/test/account-deletion.benchmark.cjs`
  with FIRESTORE_EMULATOR_HOST=127.0.0.1:18080. Separate demo-only database, 2,000
  unrelated and 50 owned synthetic messages, mocked Auth/storage: 10 batches,
  66.316 seconds active elapsed time. This implies ten daily invocations versus
  roughly 50 minutes at a five-minute cadence for that fixture with no backlog.
  It is NOT a production SLA or a measurement of production storage/network speed.

Cloudflare preparation:

- Created only the new ccs-account-deletion-scheduler Worker in account
  77cd306e2d923f8e921fcdd0544c2e03. Scheduled handler source deployed (initial
  code version 000444ad); public HTTP handler verified to return 404.
- Five-minute cron configured, but ENABLED=false. No database/storage bindings
  and no deletion requests sent by this Worker.
- Separate ACCOUNT_DELETION_WORKER_SECRET is supported by the backend alongside
  the existing CRON_SECRET. After explicit user approval, the same newly generated
  credential was saved as an encrypted Cloudflare production secret and a Vercel
  CCS Production Secret environment variable. Both saves were verified in their
  dashboards. Vercel requires a new deployment before that value takes effect;
  no live redeployment or scheduler activation was performed in this step.
- Existing Cloudflare services, bucket, object permissions, domains and upload
  configuration were not changed. No paid plan or subscription was enabled.

Remaining release gates (do not describe deletion as ready yet):

Isolated Vercel verification: deployment dpl_HoNjKHK9h6Y7NoHggfuh5apinDhM at
https://ccs-phj6w2em5-ccs-projects1.vercel.app is ready, with deletion explicitly
disabled and no cron configured. It was assembled from the verified production
manifest plus deletion changes, rather than deploying the entire working tree.
An authenticated CLI smoke check returned 503 for a deletion request and 200 with
status unknown for a synthetic receipt. No real account was queued. The live
https://ccs-wine.vercel.app domain was checked afterward and still resolved to
the previous deployment dpl_5FTSDQNgK4nZ4UZSHDMuH23w8jTP. This isolated deployment
has not been promoted to the live app domain.

After saving the approved scheduler secret, redeployed the same isolated source
with Production environment configuration: dpl_4wGam8WDbaQZXd25jS9ndyMFeD9e,
https://ccs-55mb7r0qv-ccs-projects1.vercel.app (READY). Explicit deletion=false
and Firebase bucket overrides were retained. Ready-deployment smoke checks:
unauthenticated GET returned 401; POST returned 503 deletion unavailable.
Post-deployment inspection again resolved ccs-wine.vercel.app to
dpl_5FTSDQNgK4nZ4UZSHDMuH23w8jTP. Successful scheduler authentication and an
actual Cloudflare-to-backend invocation are NOT yet verified; the Worker remains
disabled and still targets the live domain, not this isolated deployment.

Subsequent verification rollout (supersedes the domain state above):
- Added authenticated GET action=verify, which only lists one object per storage
  provider and reads Firebase bucket retention metadata. It never advances the
  queue or records worker health. Responses contain capability flags and retention
  durations only, not filenames or provider error messages.
- Tests prove verification cannot use queue/Auth/database dependencies and does
  not log object names or upstream errors. Four new offline cases pass (22 offline
  tests total; 44 across the previously run emulator and Flutter suites).
- Published dpl_J3eUgVHF1uBrpAkqrKxtXJye1Dw4 to ccs-wine.vercel.app with
  ACCOUNT_DELETION_ENABLED=false. Existing production handlers were compared with
  the retained production baseline and unchanged; community routing and vercel.json
  changed only to add deletion support. Prior rollback target is
  ccs-h6835jsxn-ccs-projects1.vercel.app.
- Live unauthenticated verification GET returns 401, deletion POST returns 503,
  Telegram status without a session returns its expected 400 and XP sync without
  a token returns its expected 401. No user data was written by these probes.
- Cloudflare has read-only VERIFY_ONLY support. ENABLED remains false. Its cron
  history confirms five-minute invocations; successful disabled no-op events are
  not proof of backend authentication or storage access.
- The first verification cron at 21:50 Kyiv time exposed a Cloudflare runtime
  incompatibility with redirect=error. Changed it to redirect=manual with explicit
  rejection of non-success responses, including 302; credentials are never forwarded
  to redirect destinations. Fixed Worker code version: 276b7881.
- The currently published verification deployment has no Vercel backup cron.
  Configure and verify that backup as part of activation, not while deletion is off.
- The 21:55 Kyiv scheduled invocation authenticated successfully and reported
  r2List=true, firebaseList=false, firebaseMetadata=false. This verified the
  actual Cloudflare-to-Vercel secret connection and R2 listing capability.
- Investigated Firebase in the console: Storage shows Get started. Google Cloud
  bucket inventory for ccsv1-63537 has no live buckets and explicitly no soft-deleted
  buckets. The bucket name in Firebase configuration is not proof of a provisioned
  legacy bucket. No storage service, billing plan or permissions were changed.
- Added FIREBASE_STORAGE_ALLOW_MISSING=true as an explicit audited deployment
  override. Only provider code 404 is tolerated; 403 and all other failures remain
  fatal. Verification distinguishes firebaseAbsent from successful listing.
  New regression test passes; offline total is 23, combined historical total 45.
- At 22:00:13 Kyiv time, an actual scheduled invocation succeeded: mode=verify,
  ok=true, r2List=true, firebaseAbsent=true. Worker version 8477c8cb; backend
  dpl_8TmKwvgwjkZjFKdkgyrkvhmV2w9R, ccs-e1ggtqoox-ccs-projects1.vercel.app,
  now assigned to ccs-wine.vercel.app. Final public deletion POST still returns503.
  VERIFY_ONLY was then returned to false; ENABLED remains false. No user account,
  Firestore document or storage object was deleted in these live checks.
- FIREBASE_STORAGE_BUCKET and FIREBASE_STORAGE_ALLOW_MISSING are deployment
  overrides, not saved project-wide variables. Preserve the audited configuration
  explicitly in a future rollout. Read/list access is proven; object deletion,
  complete account cleanup and device end-to-end flow still need disposable tests.

1. Connect the scheduler credential, deploy a verified compatible backend, then
   confirm authenticated scheduled invocations and the daily backup in live logs.
2. Measure production dataset/queue size and Firestore operations. A whole-database
   scan remains: there is no complete persistent ownership index. Frequent scheduling
   addresses delay but does not remove scan cost or guarantee free-tier capacity.
3. Finish auditing legacy/orphan R2 media ownership and public-media caching.
   R2 deletion has passed the disposable live test below. This Firebase project
   has no live or soft-deleted Storage buckets; missing-bucket behavior is verified.
4. Verify all deployed writers and rules prevent new references/copies to deleting
   accounts after the scan has passed. The old backend and public clients still
   exist; local recipient checks alone cannot provide this guarantee.
5. Test loss of request response and the complete in-app flow on devices. Real
   Auth removal and interrupted-batch recovery passed the synthetic live test below.
6. Sign in with Apple is absent from the current auth implementation. When added,
   its token revocation must be integrated into deletion before App Store release.
7. Set user-facing completion/retention timelines from verified operational results,
   then update the published Terms and Privacy Policy. No new timing promise has
   been published and account deletion remains disabled for public users.

## Disposable live deletion test — 1 October 2026

User explicitly requested this test. Ran the real worker and storage adapter from
a one-off Vercel build with existing Production credentials and deletion disabled.
No HTTP test endpoint was created. The real Firestore pager was replaced by an
explicit fixture-path list: no full database scan was run, and only newly created
synthetic users/private chat records were eligible for mutation. Auth and media
adapters rejected any UID or prefix outside the test account. No real user's
profile, chat or file was included.

Run ID: 2d6ead6f6a5d47e3aced6071. Test source:
telegram_auth_server/test/account-deletion.live.cjs.

Live result: PASS, seven batches, 18,874 ms active elapsed time:
- Synthetic Firebase Auth account deleted; its profile and private child data gone.
- Owned chat message removed; the other synthetic user's reply retained with its
  quoted content cleared. Chat membership transferred to the control account.
- Two real R2 objects (users/ and garage/ prefixes) removed. Control Auth account,
  control profile and control R2 object were verified intact before fixture cleanup.
- Deliberately interrupted the first media batch. Lease was released, Auth remained
  disabled and present, and subsequent batches resumed and completed successfully.
- Completion receipt was written and temporary task/reference indexes were empty.

Afterward all control fixtures were cleaned up. An independent read-only build
confirmed absence of both Auth accounts, all eight tracked document paths, all
three R2 objects and every test-job subcollection. These fixture receipts/tombstones
were removed explicitly as test cleanup, not by shortening production retention.

Evidence in Vercel build logs:
- dpl_Dh1WmqPGunkGUdz3mJ11NsnZsuSe: CCS_DELETION_LIVE_TEST ok=true and cleanup ok=true.
- dpl_5Z22PwQbqukZrdKk7cyt1swfQs5f: CCS_DELETION_FIXTURE_ABSENCE ok=true.
Both one-off builds show deployment Error because they produced no public website
output directory AFTER their test scripts passed. Neither was published to the app
domain. Live domain still resolves to dpl_8TmKwvgwjkZjFKdkgyrkvhmV2w9R and deletion
POST still returns503. No APK was built.

Limits: this proves real Auth/Firestore/R2 integration for these fixtures, not an
end-to-end in-app request, full production scan throughput, all legacy spot-media
ownership, cache expiry, or permission coverage of every deployed writer. The
19-second fixture result is NOT a public deletion SLA. Keep public deletion off
until the remaining gates above pass.

## Device test preparation — pro100_bro

The user created a disposable account and identified it by username. An exact,
read-only Firestore lookup found one matching profile and an active Auth account.
Pinned ACCOUNT_DELETION_TEST_UID to that resolved UID as a deployment override;
the username is not an authorization mechanism. ACCOUNT_DELETION_ENABLED remains
false. Requests from other authenticated UIDs are rejected even if their request
body supplies the test UID or username.

Added scope.js and restricted runDeletionQueue(onlyUid): it reads only the target
job, uses separate hashed scheduler health/lease state, and skips global receipt
and tombstone purging. This limits queue selection, not the worker's traversal:
after the user's confirmation the current worker still scans production collections
for references belonging to that one UID. Full-scan cost/latency is still a release
gate, and the live synthetic benchmark must not be used as its SLA.

Validation: 25 offline checks and 14 emulator tests passed, including other-account
rejection, separate health requirements, unchanged public scheduler state and
untouched unrelated queue entries/expired metadata. Previously run Flutter tests
remain 9. No client changes or APK build in this step.

Deployment dpl_4podvCmx63XyN47aNSySwrFbBkpk at ccs-mun7p78u5-ccs-projects1.vercel.app
is ready and assigned to ccs-wine.vercel.app. Cloudflare ENABLED=true now invokes
this restricted backend; VERIFY_ONLY=false. This does NOT enable public deletion.
Unauthenticated request and scheduler probes both return401.

Before-deletion baseline from read-only build dpl_H4nU1o68bkVF4EHuyEfgbmezXMh1:
profile/Auth exist, Auth not disabled, avatar configured, users/{uid}/ contains one
object, garage/{uid}/ contains one object (neither listing truncated), and there
is no deletion request. The user's app confirmation is still required. After this
test, remove the test-only scheduler state and disable the temporary gate/scheduler;
keep the completion receipt available for the app's confirmation before retiring it.

Readiness verified at 22:30:13 Kyiv time: actual Cloudflare scheduled invocation
returned ok=true, busy=false, attempted=0, pending=false. Worker configuration
version 2c3c0805. The scoped scheduler health is now fresh and the account has not
been queued or deleted. The user can sign out/in for recent authentication and
confirm deletion inside the app. Keep the receipt and app installation until
completion has been checked. No additional APK is required for this server change.

Device confirmation received October 1 at 22:32:09 Kyiv: request queued, profile
marked deleted and Auth disabled. The user subsequently confirmed the processing
message and status button ARE visible (the earlier missing-UI report was corrected).
Read-only verification deployment dpl_3gigdmT5BUPieonhA1VuW3pvyX6t observed
processing after the 22:40 and 22:45 cron runs, lastRunOk=true, 43 queued tasks,
first root xp_transactions. Auth/profile still exist; completion and media removal
are NOT verified. A successful cron run is not evidence of deletion completion.
The six-minute upload cooldown is a minimum before work begins, not an SLA.
The full scan and seven-second per-job slice remain a release performance blocker.
Do not disable the scheduler while this confirmed deletion is unfinished.

Client status refresh now shows Checking… with the button disabled during the
request, and an explicit still-processing result after a successful refresh.
This fixes the apparent unresponsive button; it does not accelerate server work.
The change requires the user's next app build (no APK built here).

October 1, 22:55 Kyiv performance update: deployed dpl_3PFMybezEaAU8iuQQimaNgdrVMmN
(ccs-qryt7gnfp-ccs-projects1.vercel.app), verified ccs-wine.vercel.app resolves to it.
Only deletion worker/queue files changed relative to the isolated production stage;
ACCOUNT_DELETION_ENABLED=false and the same single test UID are retained.
Worker now reads/commits up to ten documents together, enumerates their child
collections concurrently, and commits its cursor atomically with deletions. The
per-invocation cap is 1,000 documents. Queue divides the 35-second window among
available jobs, so a lone job no longer wastes four of five slots. Added progress
time/document counters. Existing saved tasks remain compatible.

Validation: 25 offline checks and 16 emulator checks passed, including a new
failed-batch rollback/resumption test and fair time allocation test. Same local
2,050-message fixture completed in 9.891 seconds active time / three capped
invocations (previous measurement 66.316 seconds / ten invocations). This is still
not a production SLA. Two Flutter refresh/error-retry widget tests passed and
targeted Dart analysis is clean. Production completion remains to be verified;
there is still no comprehensive ownership index or validated public timeline.

October 1, 23:20 Kyiv: production aggregate counts exposed the dominant scan cost:
343,600 root documents, including 200,691 push_deliveries and 128,326
user_notifications. The bounded manual run stopped after 20 worker invocations;
it did not complete deletion. The garage prefix was empty; avatar prefix still
contained one object. Do not present this as a successful completed deletion.

Deployed indexed cleanup in dpl_4St4qcSzAqKmMYrKiz5HdiUXpVzw
(ccs-d1o9fxf4b-ccs-projects1.vercel.app), assigned to ccs-wine.vercel.app with the
same test-only UID restriction. It uses existing single-field equality indexes
for delivery recipients and notification identity fields, including nested data
fields. Deleting spots/topics/messages schedules targeted copied-notification
cleanup. Chat message copies check both chat and message ID to avoid collisions.
Old jobs with unconvertible hashed references retain the full notification scan
rather than skipping copied content. No rules/index definition deployment needed.
19 emulator tests and 25 offline tests pass, including indexed pagination,
preservation of unrelated recipients, legacy fallback and chat-ID collision checks.
This removes the two dominant scans, not every scan or every legacy-schema audit.
Production verification is ongoing. The temporary test configuration is retained
until the accepted deletion completes; public deletion remains disabled.

Final verification and retirement (supersedes the preceding in-progress notes):
worker shortcut for an empty deleted-source index passed 20 integration tests and
was deployed as dpl_HAVpQif2jeMnjWRtzrVUQMouXgg3. Account deletion completed at
23:37:50 Kyiv. Diagnostic build dpl_5dbEFC9KdxkSZvbgW3xLxuhyCjHa logged the
complete receipt plus independent Auth/profile/username/subcollection/R2/owned
history absence checks. dpl_EwhLDcRfnPueLpSSWcSQBaugCdc9 repeated the checks and
removed only the completed test's marker and scheduler state at 23:40:36, after
the observed token-expiry safety window. It preserved the anonymous receipt.
These unpromoted diagnostic builds intentionally have no public output directory;
their final Vercel build Error is not an application deployment failure. Judge
their explicit verification markers, not the outer build state.

Live backend was then retired to dpl_4Bkm6ZwuA8X3QCcWyFasopmbogrW (same fixes,
ACCOUNT_DELETION_ENABLED=false, empty ACCOUNT_DELETION_TEST_UID). Canonical alias
updated; unauthenticated new-request probe returns 503 as expected. Cloudflare
ENABLED=false and VERIFY_ONLY=false were verified in its settings. No existing
bucket, billing plan, general backend endpoint, app build, or Firestore rule
configuration was changed during this test. Source changes remain uncommitted.








