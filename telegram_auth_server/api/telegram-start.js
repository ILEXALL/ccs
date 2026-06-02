const crypto = require('crypto');
const { db } = require('../lib/firebase-admin');
const {
  publicBaseUrl,
  telegramBotToken,
  telegramBotUsername,
  telegramWebhookSecret,
} = require('../lib/telegram');

async function ensureTelegramWebhook() {
  const webhookUrl = `${publicBaseUrl()}/api/telegram-webhook`;
  const secret = telegramWebhookSecret();
  const response = await fetch(
    `https://api.telegram.org/bot${telegramBotToken()}/setWebhook`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url: webhookUrl,
        allowed_updates: ['message', 'edited_message'],
        ...(secret ? { secret_token: secret } : {}),
      }),
    },
  );
  const result = await response.json();

  if (!response.ok || result.ok !== true) {
    throw new Error(result.description || 'Could not configure Telegram webhook.');
  }
}

module.exports = async (request, response) => {
  try {
    if (request.method !== 'GET' && request.method !== 'POST') {
      response.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const sessionId = crypto.randomBytes(18).toString('base64url');
    const botUsername = telegramBotUsername();
    await ensureTelegramWebhook();

    await db.collection('telegram_login_sessions').doc(sessionId).set({
      status: 'pending',
      createdAt: Date.now(),
      updatedAt: Date.now(),
    });

    response.setHeader('Cache-Control', 'no-store');
    response.status(200).json({
      sessionId,
      loginUrl: `https://t.me/${botUsername}?start=login_${encodeURIComponent(sessionId)}`,
    });
  } catch (error) {
    response.status(500).json({ error: error.message });
  }
};
