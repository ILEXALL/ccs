# App Store baseline — 30 September 2026

## Source selected by the user

Local `alex-ui` was fast-forwarded from `595c17b2` to `89e2c84c`, matching
`origin/zhena-ui` (29 September, `optimisation + fixes`). No remote push was made.
The separate `codex/release-live-readiness` worktree and
`codex/release-server-verification` branch were not merged or cherry-picked.
They remain available as historical work, not part of this release baseline.

Older release notes describe work on several branches. Their claims must not be
treated as proof that a feature exists in this selected tree or production.

## Verification on this Mac

- Flutter 3.47.4 / Dart 3.13.3; Xcode 26.3 (17C529).
- 15 targeted Flutter tests passed: camera method channel, keyboard dismissal,
  consent gate, presence marker, dwell marker and public group card.
- Release iOS compilation succeeded in 113.9 seconds. Output:
  `build/ios/iphoneos/Runner.app`, 105.0 MB, version `1.0.9 (13)`.
- Local Flutter resolved four SDK-constrained transitive dependencies differently
  from the incoming lockfile: matcher, meta, test_api and vector_math. These local
  verification results use that resolution, not the exact incoming lockfile.
  The incoming lockfile was restored after verification; no dependency upgrade
  is retained in the working tree.
- Unauthenticated GET to the configured production `/api/account-deletion`
  returned HTTP 404. No deletion request or authenticated user operation was sent.

Logs (local only): `/private/tmp/ccs-ios-release-2026-09-30.log` and
`/private/tmp/ccs-ios-regressions-2026-09-30.log`.

## Remaining release work

1. Configure and verify Apple login in Apple Developer/Firebase and on device.
   The local implementation described below is ready for that configuration;
   unsigned compilation does not verify provider activation or provisioning.
2. Finish and deploy account deletion with the required server configuration,
   rules and media cleanup verification. A client screen alone is insufficient;
   the production route is currently unavailable. Assess the implementation in
   this baseline before activating it.
3. Verify camera permission denial, capture/cancellation, rotation, photo upload,
   keyboard/send-button access and map behaviour on actual iPhone/iPad devices.
   Unit/widget tests do not establish these device results.
4. Prepare a signed archive with the map build configuration. The diagnostic
   compilation uses no signing or CARTO key and is not a distributable release.
   The source still declares `1.0.9+13`; inspect App Store Connect before choosing
   a new unused build number. No IPA upload or review submission has occurred.
5. Recheck reviewer access, content rights, moderation, privacy declarations and
   any pending agreements in the live console before submission. Historical
   notes are not a current console verification.

Apple references checked 30 September 2026:
- https://developer.apple.com/app-store/review/guidelines/#login-services
- https://developer.apple.com/support/offering-account-deletion-in-your-app/

## Stage 1 — local Apple sign-in implementation

Completed locally on 30 September; the user requested a stop after each stage.

- Added the native `ASAuthorizationAppleIDButton` on iOS, with Apple's system
  localization, accessibility and logo. Other platforms keep their login options.
- Used the existing Firebase SDK's `AppleAuthProvider` native flow with name/email
  scopes, existing nickname onboarding, profile saving and account restrictions.
  User cancellation exits quietly; profile setup failure signs out of Firebase.
- Added the Apple sign-in entitlement. No new package dependency.
- Made the login screen safe-area aware and scrollable for smaller viewports.
- Four tests passed: returning Apple provider/missing profile fields, native
  button channel and disabled taps, small iOS viewport, Android login options.
- Targeted Dart analysis passed. Unsigned release iOS build passed in 48.5 seconds
  and produced a 105.0 MB app. This remains a diagnostic build without CARTO key.
- No console configuration, signed distribution, real Apple account login,
  backend deployment or upload was performed in this stage.

Next stage: inspect/enable Apple sign-in for `lv.ilexall.ccs` and Firebase,
refresh provisioning as needed, then verify real first/repeat/cancel login with
both shared and hidden email on a device. Before release, the account-deletion
stage must also implement Apple authorization revocation; adding login does not
close that deletion requirement. Do not claim end-to-end readiness yet.

Implementation reference:
https://firebase.google.com/docs/auth/flutter/federated-auth#apple

Stage logs: `/private/tmp/ccs-apple-tests.log`,
`/private/tmp/ccs-apple-analyze.log`, `/private/tmp/ccs-apple-ios-build.log`.

## Stage 2 — client authorization for Apple account deletion

User deferred manual device checks until the assembled publication build.
Automated local checks continue; this is not permission to claim production
readiness or to skip the eventual signed-build verification.

- Apple-linked accounts now reauthenticate the existing Firebase user before
  requesting deletion. Mismatched accounts, absent authorization codes, expired
  authentication and missing Firebase tokens stop the request.
- The client revokes the Apple grant using Firebase's
  `revokeTokenWithAuthorizationCode` before submitting backend deletion. A
  revocation failure propagates; Apple cancellation quietly restores the UI.
- One-use Apple codes remain in memory only. Existing accepted-request receipt
  recovery runs first, without trying to reauthenticate a disabled account.
- Non-Apple accounts retain the existing recent-login requirement.
- 14 tests passed (10 deletion authorization/UI checks and 4 Apple login tests).
  Targeted static analysis passed. Test doubles do not verify real Apple grant
  revocation. No new iOS archive was generated for this Dart-only stage.
- No Firestore rules, backend code, production configuration or live accounts
  were changed. Nothing needs copying into Firebase Rules for this stage.

Next stage: finish the server deletion implementation and rollout preparation
against this selected baseline. Review descendant cleanup, legacy media ownership,
  upload access and practical queue completion before enabling it. Production
  endpoint availability, cron execution and actual cleanup remain unverified.
  Revocation and backend acceptance are separate network operations: if backend
  submission fails after revocation, do not display deletion as complete; use the
  receipt/status recovery and retry. Review this on-device during final validation.

Logs: `/private/tmp/ccs-deletion-client-tests.log` and
`/private/tmp/ccs-deletion-client-analyze.log`.
