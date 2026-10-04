# CCS Telegram Auth Server

This backend makes Telegram login real for the CCS Flutter app.

The Flutter app must never store the Telegram bot token. The token lives only on this backend.

## Environment Variables

Set these in Vercel:

- `PUBLIC_BASE_URL`
  - Example: `https://ccs-telegram-auth.vercel.app`
- `TELEGRAM_BOT_USERNAME`
  - Example: `ccs_login_lv_bot`
- `TELEGRAM_BOT_TOKEN`
  - Token from BotFather. Keep it secret.
- `FIREBASE_SERVICE_ACCOUNT_JSON`
  - Full Firebase service account JSON as one environment variable.

## BotFather

After deployment, set the bot domain:

```text
/setdomain
```

Choose the CCS bot and enter the Vercel domain without `https://`.

Example:

```text
ccs-telegram-auth.vercel.app
```

## Flutter

After deployment, paste the backend URL into `telegramAuthBaseUrl` in:

```text
lib/main.dart
```

Example:

```dart
const telegramAuthBaseUrl = 'https://ccs-telegram-auth.vercel.app';
```

## XP Stage 1

The backend includes `api/xp-sync.js` for CCS XP System v1.0.

Supported actions:

- `ensure_config`: admin-only; creates `app_config/xp` with XP disabled by default.
- `sync_me`: authenticated user; evaluates profile and first garage car awards.
- `sync_user`: staff-only; evaluates another user's profile and first garage car.
- `sync_spot`: spot author or staff; evaluates approved permanent spot awards.

The client never sends XP amounts. It only requests a sync, and the backend reads
Firestore with Firebase Admin SDK before writing `xp_transactions`,
`xp_user_weeks`, and `xp_user_stats/{uid}`.

Default `app_config/xp`:

```json
{
  "levels_enabled": false,
  "xp_awards_enabled": false,
  "enabledUserIds": [],
  "weeklyLimit": 3000,
  "timezone": "Europe/Riga",
  "rulesVersion": "ccs-xp-v1.0"
}
```

Keep both flags disabled during deployment. For tester-only rollout, add Firebase
Auth user IDs to `enabledUserIds`. Use `["*"]` only when XP should be available
to everyone. Enable both flags only after the Vercel route and Firestore
rules/indexes are deployed.
# Manual admin XP awards

The mobile Admin → Users → user three-dot menu → **Award XP** opens the form
with that recipient selected. Enter 1–3000 XP and a required reason (up to 500 characters); verify the
recipient and confirm. The reason is visible in the recipient's XP history and
the admin audit record. This is a lifetime XP adjustment and does not consume
weekly earning capacity or affect weekly rankings. No push message is sent.

`admin_xp_grant_target` resolves the recipient with an authenticated admin check.
`admin_xp_grant` requires the verified `userId`, `username`, `amount`, `reason`,
and stable `requestId`. Authority, recipient identity and deletion status are
checked within the transaction. Self-awards and blocked/deleted recipients are
rejected. Balance, level, ledger and audit commit together; existing revoke/
restore handling supports these awards. Mobile pending requests are retained
per admin account across restarts; retry after an uncertain result instead of
creating another award. Explicit validation failures permit correction.

Server redeployed on 4 October 2026: `dpl_HLhaa87Ay6HxDASvDXoW1e8aACTo`,
`https://ccs-ev1xu2qn4-ccs-projects1.vercel.app`, serving
`https://ccs-wine.vercel.app`. Live unauthenticated requests return HTTP 401.
Deployment used the previous production snapshot plus `handlers/xp-sync.js`
and `lib/xp/admin-grants.js`; account-deletion worker source was preserved.
The earlier XP deployment omitted a deployment-only deletion test UID and
caused scheduler HTTP 503 responses. Restored that same test UID as the
production project variable `ACCOUNT_DELETION_TEST_UID` and redeployed;
public deletion remained disabled during testing. After confirming the old test job complete,
the user authorized switching the sole test account to `hoedeadlov` for iOS
testing. Also restored the previously audited `FIREBASE_STORAGE_BUCKET` and
`FIREBASE_STORAGE_ALLOW_MISSING=true` as production project variables; their
omission caused HTTP 500 after the scope was restored. The normal October 3
16:45 Kyiv run is verified in the scoped scheduler record: `lastRunOk=true`,
`attempted=0`, `pending=false`. This verifies scheduling, not iOS deletion yet.
October 4: the approved read-only verification confirmed the iOS test account's
Auth/profile/username and checked related rows absent, zero profile child
collections, no remaining job work rows, and empty avatar/garage R2 prefixes.
`ACCOUNT_DELETION_ENABLED=true` now takes precedence over the retained test UID;
all authenticated users can request their own deletion once shared scheduler
health is fresh. Shared health was verified at October 4 23:00 Kyiv:
`lastRunOk=true`, no pending jobs, lease released. Five-minute Cloudflare calls continue; Vercel daily backup
`0 3 * * *` is configured (03:00 UTC; its first actual daily run is not yet verified).
Roll back new-request availability by restoring the prior test-only deployment
`ccs-hol4oajnc-ccs-projects1.vercel.app` only when no public deletion jobs are
pending; otherwise preserve processing of accepted jobs during incident recovery.
The mobile app still needs rebuilding to expose the new control.
No Firestore rules changes are required. The new UI has widget coverage but
still needs a real-device check after deployment. The one-off Eugene_e34 award
was already applied through Cloud Shell and must not be repeated as a smoke test.

Tests: `node --test --test-isolation=none test/admin-grants.test.js`;
with the local demo emulator at 127.0.0.1:18080, run
`node --test --test-isolation=none test/admin-grants.emulator.cjs` with
`FIRESTORE_EMULATOR_HOST=127.0.0.1:18080`.
