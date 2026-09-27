# Release verification — 27 September 2026

Status: not ready for production deployment or submission. Server fixes have been
deployed to a preview; this is not evidence that production deletion, Apple login,
or the replacement iOS build works.

## Production rules rollback — 27 September, 18:42 local time

The user manually published the replacement rules at 18:31, then explicitly asked
to restore the preceding version to keep build 13 working. Restored the immediately
previous console version (20 September, 21:33), capturing all 2,907 numbered lines
from the history editor and verifying the staged text matched before publication.
Firebase confirmed successful publication at 18:42 and warned propagation can take
up to a minute. Backup: `build/firestore-restored-2026-09-20.rules`; confirmation:
`build/firestore-rules-restored.png`. Repository `firestore.rules` remains the new
release candidate; do not deploy it again until the coordinated migration. No
Vercel production changes, deletion activation or data deletion occurred during
this rollback. Build-13 device flows have not been retested after restoration.

## Earlier preview deployment — 27 September 2026

- Git branch `codex/release-server-verification`, commit `81f7906` contains the
  first server changes. The later `fec6545` preview below supersedes it;
  neither deployed production or Firebase rules.
- Vercel deployment `dpl_4dCURLqJYW1hHNU1L9EpxJgjKgHS` is Ready in Preview:
  https://vercel.com/ccs-projects1/ccs/4dCURLqJYW1hHNU1L9EpxJgjKgHS
- Host: https://ccs-kaf1eisgt-ccs-projects1.vercel.app
- Live checks through authorized Vercel preview access, without a Firebase token:
  deletion POST returned 503 (disabled); deletion GET returned 401 (cron auth);
  upload POST and XP sync POST returned 401; synthetic nonexistent receipt lookup
  returned 200 with `status: unknown`, confirming Firebase connectivity.
- Preview has no deletion enable flag, cron secret or R2 configuration. The handler
  fails closed. No destructive worker or R2 operation was exercised; daily production
  scheduling, actual deletion completion and upload compatibility remain unverified.
- No production promotion or Firebase rules deployment was performed.

## Subsequent preview and group-creation migration

Latest verified deployment: commit `06dfedf`, Vercel
`dpl_DhDQAaSLtnTaM693h7Ze42KpbDpT`, Ready in Preview:
https://ccs-kyign6knd-ccs-projects1.vercel.app . Live empty POST checks returned
401 for group creation, 401 for uploads and 503 for disabled account deletion.
All three returned `Cache-Control: no-store`. No records or files were created by
these checks. Production hosts, deployed Firebase rules and build 13 are unchanged.

Commit `fec6545` deployed successfully to
https://ccs-k10bfdnq9-ccs-projects1.vercel.app
(`dpl_3VqZxnLwxNY9t1NsNCKYT7MGVWuD`). Live checks confirmed disabled deletion
(503), authenticated upload enforcement (401 without a token), and Firebase
connectivity (200/unknown for a synthetic deletion receipt).

The user chose to preserve sharing to eight groups by moving creation to the server.
The new `/api/group-spot-create` route shares the existing community function.
It atomically creates the spot, canonical forum topic and up to eight group links,
checking consent, deletion status, bans, country restrictions, every membership,
photo namespace/reservation and moderation permission. Repeated identical requests
for the same spot ID are idempotent. The replacement Flutter client uses this route;
new rules reject direct group-spot creation. Do not deploy these rules while build
13 clients still need to create group spots. Public spot creation remains direct.

Rule helpers now avoid repeated role/auth evaluation that exceeded the expression
budget in automatic-topic updates. Emulator fixtures explicitly seed consent and
reset isolated demo projects between runs.

Validation: 254 offline server tests, 102 emulator checks and 286 Flutter tests.
Emulator checks cover eight-group atomic creation, concurrent duplicate requests,
full rollback on an existing topic, regional moderation, denial without consent or
membership, deletion tombstones, bans, foreign uploads, expiry and a ninth group.
Reading as a member only of the eighth group also passes. Targeted Flutter analysis
reports no issues. Real authenticated uploads, native iOS flows and production
scheduling remain unverified. These changes are preview-only until the coordinated
migration; they do not authorize enabling deletion.

## Implemented and checked locally

### Deletion and build-13 migration follow-up

The user confirmed build 13 is still used and must remain working during migration.
Its legacy upload service is unchanged. A non-destructive empty POST to
`https://ccs-telegram-auth-server.vercel.app/api/r2-presign-upload` returned
400 `Missing path` on 27 September; this confirms its tokenless request path,
not an end-to-end file upload.

- The replacement client now uses the canonical authenticated upload service with
  no legacy fallback, sends the signed Cache-Control header, and uses distinct
  uploader namespaces and timestamp filenames for spot photos so different editors
  cannot overwrite another uploader's ownership record. The namespace also lets
  deletion scrub that editor's photo URLs from another user's spot.
- Server upload authorization and the `media_uploads` ownership record commit in
  one transaction before the signed URL is returned. The server checks current
  consent, bans, deletion state, key ownership and spot ownership. Draft spot IDs
  are reserved; matching rules prevent another client from claiming the draft.
- Deletion uses the native `media_uploads.uid` index to remove exact objects,
  including abandoned drafts. Storage failures retain the ledger row for retry.
  Resumable jobs created before this change acquire the new media-cleanup task.
- New objects get a server-controlled five-minute cache policy. Existing object
  metadata, CDN overrides, already cached copies and old-host uploads are unaffected;
  this does not establish a five-minute erasure guarantee.
- The remaining exhaustive scan batches reads/cursor writes per page and parallelizes
  bounded child discovery. It still traverses missing parents and subcollections.
  A lone account can use the queue budget; multiple accounts share it fairly.
- Native indexed queries clean up reply previews and copied spot/topic references
  even after their collection was scanned. The new `spot_links.spotId` collection-group
  index in `firestore.indexes.json` must be deployed and READY before enabling deletion.
  Quote-creation rules reject missing sources and authors with a deletion tombstone.
  Deferred media checks also remove legacy spot-photo URLs from shared records after
  the source spot has been deleted, regardless of scan order.
- Deletion now additionally requires `ACCOUNT_DELETION_LEGACY_UPLOADS_RETIRED=true`.
  Leave it unset/false while build 13's upload service remains active.

These indexes cover uploads and the declared content relationships, not every
possible historical data shape. The exhaustive scan is retained as a safety net.
Legacy orphan files with no surviving owner record still need an inventory and an
explicit resolution; the new ledger cannot reconstruct missing historical ownership.

Revised emulator throughput (synthetic rows, fake Auth/R2, seven-second slices):

| Fixture | Calls | Measured durations | Unrelated rows preserved |
| --- | --- | --- | --- |
| 1,000 rows, 100 owned | 1 | 2,502 ms | 900 |
| 10,000 rows, 1,000 owned | 5 | 7,068 / 7,140 / 7,118 / 7,112 / 1,922 ms | 9,000 |

These fixtures measure the broad scan, not a workload with many spots, quotes or
R2 objects. Indexed dependent cleanup adds workload. Do not infer a production SLA.
Reports: `build/deletion-benchmark-1000.json`, `build/deletion-benchmark-10000.json`.

Migration gates:

1. Keep the old host and production rules in place while testers depend on build 13.
2. Test the replacement client's sign-in, consent and real authenticated R2 upload
   against the configured canonical service using a disposable account.
3. Migrate testers and retire the legacy upload route. Wait for previously signed
   URLs to expire; resolve legacy orphan ownership and cache/backup retention.
4. Deploy/verify the new index and consent/quote/reservation rules in the coordinated
   cutover. Consent rules would block build 13's writes because it has no consent UI;
   do not deploy them early while promising full build-13 compatibility.
5. Verify production-like deletion and scheduled runs, establish the actual deadline,
   then enable deletion and update public text. Do not set either enablement flag now.

Follow-up checks: 254 offline backend tests, 34 emulator checks and 285 Flutter tests
(including two local HTTP upload transport tests) passed. Edited upload Dart files analyze without issues.
The tests use synthetic accounts/storage; they do not prove real R2 deletion or
native iOS behavior.

- Apple native Firebase sign-in on iOS/macOS, using normal nickname/profile and
  terms gates. Settings can explicitly link Apple to the currently signed-in
  Google/Telegram account, retaining its Firebase UID. Conflicting identities are
  rejected; the app does not merge accounts by matching email. Linking requests
  explicit consent. Existing Telegram profile metadata survives Apple sign-in.
- Added the iOS Sign in with Apple entitlement. Linked Apple users reauthenticate
  and revoke Apple's authorization before requesting account deletion.
- Login content scrolls on short screens after adding the Apple option.
- Terms acceptance now gates mutations using `isActiveUser`. Account reads,
  profile bootstrap, username reservation and consent recording remain available
  before acceptance. This is not an audit of every Admin SDK endpoint or every
  allowed profile field; those require further review before deployment.
- Closed chat-rule gaps: banned accounts cannot send/edit messages; direct blocks
  prevent both sending and editing in both directions; chat preview changes also
  require an active account with consent.
- Deletion propagates parent deletion into descendant tasks, including another
  author's replies beneath a deleted topic/spot. Existing detached descendants are
  still enumerated. Username reuse no longer clears a quote with a different
  explicit message ID.
- Queue wraparound fills the remaining daily slots. A failed account still advances
  the cursor. Scheduler state now records start/end timestamps, elapsed time,
  attempted jobs and success/failure. Ordering is round-robin by UID, not FIFO.
- R2 adapter tests cover partial delete errors, network failures, unsafe prefixes,
  retry from prefix start and completion only after an empty listing.
- CARTO/OpenStreetMap attribution is always visible rather than hidden in a popup;
  CARTO links to its attribution page. Device layout verification is pending.
- `npm test` now discovers all offline server tests instead of only a subset.
  Codemagic runs Flutter analysis/tests and server tests before archive/upload.
  Existing analysis warnings are nonfatal in CI; compile errors remain fatal.

## Verification results

| Check | Result | Limit |
| --- | --- | --- |
| Offline backend | 249 passed | Doubles, not production |
| Firestore emulator | 26 passed | Actual rules/transactions; synthetic Auth and R2 |
| Full Flutter suite | 283 passed | Widgets/unit tests; not iPhone/iPad sign-in |
| Full Flutter analysis | No compile errors; 127 diagnostics at first run | Includes existing warnings/info and four new lint messages subsequently fixed |
| Final edited-file analysis | No compile errors; five pre-existing map lint messages | Native entitlement/provider setup not checked |
| Git diff whitespace check | Passed | CRLF normalization notices only |

The old `MainScreen` widget test assumed the region gate came first and accessed
uninitialized Firebase after the consent gate was introduced. It now explicitly
tests that accepted consent still leads to the region gate. It does not claim an
end-to-end authenticated `MainScreen` test.

Logs/reports are in ignored `build/release-server-tests.json`,
`build/release-emulator-final.log`, `build/release-flutter-final.log`, and
`build/deletion-benchmark.json`. No credentials are stored in these reports.

## Deletion throughput and unresolved completeness

The local benchmark used 1,000 synthetic documents, 100 belonging to the deleted
account, a 7,000 ms budget and the actual 250-document limit. It required five
invocations: 7,086 / 7,072 / 7,071 / 7,085 / 3,811 ms. All 100 owned rows disappeared;
all 900 unrelated rows remained. Auth and media were doubles. This is not a
production benchmark or a guaranteed completion deadline.

At one daily invocation per account this fixture requires about five daily runs.
Even zero network latency cannot scan 10,000 rows in fewer than 40 job invocations
at the current cap; backlog, quotes, media, retries and network latency add time.
This was the original slow implementation; see the follow-up measurements and
native relationship/upload indexes above. A universal authoritative index is not
implemented, and production throughput has not been measured.

The index must include owned documents, relationships, copied identities, quotes,
media prefixes and descendants. It needs a verified legacy backfill and atomic
maintenance across Flutter writes and every backend writer. Do not switch deletion
to an incomplete/stale index or regard a best-effort client index as authoritative.
Production schema/volume and a free-hosting-compatible maintenance mechanism still
need verification. Do not enable deletion while this remains unresolved.

Other open checks: media from abandoned spot uploads with no surviving spot row;
copied spot/topic content referenced only by IDs; writes arriving after a collection
was scanned; legacy server upload URLs; CDN/client caches and backup retention.
Current uploads advertise a one-year public cache lifetime. R2 object removal alone
does not prove that every cached copy is immediately inaccessible.

The configured cron is daily at 03:00 UTC. This has not been deployed or observed
running. After a verified deployment, check the scheduler timestamps and deployment
logs across real scheduled runs, including failure/recovery; a manual invocation
does not establish daily scheduling. Public documents and app text must not promise
24-hour completion. No production completion timeline has been established.

## Moderation and content rights

Reporting, blocking and bans exist, but Apple review readiness is not established.
There is no verified comprehensive pre-publication filter for chat text/images.
Content-specific reporting, hiding blocked users across shared feeds, moderator
response coverage, removal evidence and repeat-offender handling need device tests
and an operational owner. Do not equate the passing rule tests with full compliance.

The current CARTO terms (25 September 2026), section 14, restrict real-time
navigation and map display on moving vehicles. CCS has driving-follow behavior;
its coverage under the account's applicable agreement is unresolved. Obtain the
applicable permission or choose a compatible provider before declaring rights.
Verify ownership/plan/usage for the existing CARTO key. No paid service was enabled.

Existing user photo permissions remain unverified. The current Terms explicitly
apply prospectively and do not retroactively license old uploads. Obtain evidence
for the existing uploads or resolve their availability before signing the Content
Rights declaration. Source attribution alone does not establish photo rights.

Primary references checked:
- https://developer.apple.com/app-store/review/guidelines/ (1.2 and 4.8)
- https://developer.apple.com/support/offering-account-deletion-in-your-app/
- https://firebase.google.com/docs/auth/flutter/federated-auth
- https://www.carto.com/legal/basemap-terms/ (13–14)
- https://www.openstreetmap.org/copyright

## Live console observations

App Store Connect was accessed read-only on 27 September:
- App 6778200005, iOS 1.0.9, Prepare for Submission; build 13 remains selected.
- Manual release selected. Sign-in required selected; reviewer username/password
  fields empty. Existing notes still describe only Google and Telegram sign-in.
- Five iPhone screenshots present. Metadata, support URL, copyright, subtitle and
  Social Networking/Lifestyle categories are populated.
- Content Rights still unset.
- App Privacy is published (console says four days ago), with the correct privacy
  URL and 14 configured data types. These cover contact info, location, contacts,
  messages, photos, support, other content, user/device IDs, product interaction and
  diagnostics. This verifies saved disclosures, not a final SDK/data-flow audit.
- App Review shows no submitted items; there is no review feedback to address yet.
- Age rating 13+ in 171 regions, 16+ Australia/Vietnam/Brazil and 15+ Korea.
  Questionnaire features: UGC/social/chat yes; parental controls, age assurance,
  unrestricted web access, under-13 social restriction and advertising no.
- Updated Apple Developer Program License Agreement pending: Apple requires the
  Account Holder to review/accept it before updating/submitting apps. Not accepted.
- Non-trader status displayed; no change made.

Vercel owner access was restored and the preview above was deployed. The local
`telegram_auth_server/.vercel` binding remains stale; do not deploy through it.
Preview deployment uses the dedicated Git branch. Production remains unchanged.

## Remaining release sequence

1. Complete authoritative deletion indexing and production-like completeness/R2
   tests, then establish a realistic deadline including queues, retries and caches.
2. Enable/configure Apple in Firebase and for `lv.ilexall.ccs`; refresh signing
   profiles and test new/returning users, Google/Telegram linking, private relay,
   conflicting identities, cancellation, retry and Apple revocation on real iOS.
3. Finish moderation filtering/report coverage and operational handling; resolve
   photo rights and CARTO driving use.
4. Test prepared review credentials through sign-in, profile creation and consent
   on the new iOS build. Credentials remain private outside this Windows repository;
   do not recreate/reset the account merely because the original Mac file is absent.
5. Coordinate rollout: build 13 cannot call the protected upload endpoint. Keep
   authentication intact, prepare the replacement client, and decide the old-build
   expiry/minimum-version rollout before changing production. The replacement source now targets
   the authenticated canonical host; build 13 retains the legacy host.
6. Deploy consent rules before distributing the new client, then verified backend
   configuration with deletion disabled. Verify storage and actual daily scheduling,
   then enable deletion. Update the already published legal pages only after that.
7. Verify the latest build number (source is still +13), create/upload the new signed
   build, verify iPhone/iPad main flows, then select it in App Store Connect.
8. Save tested review access/notes, complete Content Rights, recheck privacy and
   export compliance against the final binary, and have the Account Holder resolve
   the outstanding agreement. Submit only after release blockers are cleared.
9. Follow Apple's review, address feedback, and manually release after approval.

No production deployment, deletion activation, public-document change, archive,
upload, submission, agreement acceptance or release occurred in this session.
