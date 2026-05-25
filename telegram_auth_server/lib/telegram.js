const crypto = require('crypto');

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function publicBaseUrl() {
  const baseUrl = process.env.PUBLIC_BASE_URL;

  if (!baseUrl) {
    throw new Error('PUBLIC_BASE_URL is not set.');
  }

  return baseUrl.replace(/\/$/, '');
}

function telegramBotToken() {
  const token = process.env.TELEGRAM_BOT_TOKEN;

  if (!token) {
    throw new Error('TELEGRAM_BOT_TOKEN is not set.');
  }

  return token;
}

function telegramWebhookSecret() {
  return process.env.TELEGRAM_WEBHOOK_SECRET || '';
}

function telegramBotUsername() {
  const username = process.env.TELEGRAM_BOT_USERNAME;

  if (!username) {
    throw new Error('TELEGRAM_BOT_USERNAME is not set.');
  }

  return username.replace(/^@/, '');
}

function verifyTelegramLogin(data) {
  const { hash, sessionId, ...telegramData } = data;

  if (!hash) {
    return false;
  }

  const authDate = Number(telegramData.auth_date);
  const now = Math.floor(Date.now() / 1000);

  if (!Number.isFinite(authDate) || now - authDate > 86400) {
    return false;
  }

  const dataCheckString = Object.keys(telegramData)
    .filter((key) => telegramData[key] !== undefined && telegramData[key] !== null)
    .sort()
    .map((key) => `${key}=${telegramData[key]}`)
    .join('\n');

  const secretKey = crypto.createHash('sha256').update(telegramBotToken()).digest();
  const calculatedHash = crypto
    .createHmac('sha256', secretKey)
    .update(dataCheckString)
    .digest('hex');

  const calculated = Buffer.from(calculatedHash, 'hex');
  const received = Buffer.from(hash, 'hex');

  if (calculated.length !== received.length) {
    return false;
  }

  return crypto.timingSafeEqual(calculated, received);
}

module.exports = {
  escapeHtml,
  publicBaseUrl,
  telegramBotToken,
  telegramBotUsername,
  telegramWebhookSecret,
  verifyTelegramLogin,
};
