# CCS App Store release — 25 September 2026

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

Current deletion traverses the database twice to find legacy and copied references.
For a large database or backlog this can take many daily runs. Before enabling, replace
that traversal with an indexed ownership inventory where necessary, verify backlog fairness,
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
