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
  "weeklyLimit": 3000,
  "timezone": "Europe/Riga",
  "rulesVersion": "ccs-xp-v1.0"
}
```

Keep both flags disabled during deployment. Enable them only after the Vercel
route and Firestore rules/indexes are deployed.
