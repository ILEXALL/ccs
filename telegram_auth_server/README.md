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
