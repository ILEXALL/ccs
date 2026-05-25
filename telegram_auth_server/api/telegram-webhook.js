const { admin, db } = require('../lib/firebase-admin');
const { telegramBotToken, telegramWebhookSecret } = require('../lib/telegram');

async function sendBotMessage(chatId, text) {
  try {
    await fetch(`https://api.telegram.org/bot${telegramBotToken()}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text }),
    });
  } catch (_) {
    // Login should still finish even if the helper message fails.
  }
}

function requestBody(request) {
  if (typeof request.body === 'string') {
    return JSON.parse(request.body);
  }

  return request.body || {};
}

module.exports = async (request, response) => {
  try {
    if (request.method !== 'POST') {
      response.status(405).json({ ok: false, error: 'Method not allowed' });
      return;
    }

    const expectedSecret = telegramWebhookSecret();
    const receivedSecret = request.headers['x-telegram-bot-api-secret-token'];

    if (expectedSecret && receivedSecret !== expectedSecret) {
      response.status(401).json({ ok: false, error: 'Invalid webhook secret' });
      return;
    }

    const update = requestBody(request);
    const message = update.message || update.edited_message;
    const text = String(message?.text || '');
    const chatId = message?.chat?.id;
    const telegramUser = message?.from;

    if (!text.startsWith('/start login_') || !telegramUser?.id) {
      response.status(200).json({ ok: true });
      return;
    }

    const sessionId = text.replace('/start login_', '').trim();
    const sessionRef = db.collection('telegram_login_sessions').doc(sessionId);
    const sessionSnapshot = await sessionRef.get();

    if (!sessionSnapshot.exists) {
      if (chatId) {
        await sendBotMessage(chatId, 'CCS login expired. Please open CCS and try again.');
      }

      response.status(200).json({ ok: true });
      return;
    }

    const session = sessionSnapshot.data();
    const ageMs = Date.now() - Number(session.createdAt ?? 0);

    if (ageMs > 10 * 60 * 1000) {
      await sessionRef.set({
        status: 'error',
        message: 'Telegram login session expired.',
        updatedAt: Date.now(),
      }, { merge: true });

      if (chatId) {
        await sendBotMessage(chatId, 'CCS login expired. Please open CCS and try again.');
      }

      response.status(200).json({ ok: true });
      return;
    }

    const telegram = {
      id: String(telegramUser.id),
      first_name: String(telegramUser.first_name || ''),
      last_name: String(telegramUser.last_name || ''),
      username: String(telegramUser.username || ''),
      photo_url: '',
      auth_date: String(Math.floor(Date.now() / 1000)),
    };
    const uid = `telegram_${telegram.id}`;
    const firebaseToken = await admin.auth().createCustomToken(uid, {
      provider: 'telegram',
      telegramId: telegram.id,
      telegramUsername: telegram.username,
    });

    await sessionRef.set({
      status: 'complete',
      firebaseToken,
      telegram,
      updatedAt: Date.now(),
      completedAt: Date.now(),
    }, { merge: true });

    if (chatId) {
      await sendBotMessage(chatId, 'CCS login confirmed. You can return to the app.');
    }

    response.status(200).json({ ok: true });
  } catch (error) {
    response.status(500).json({ ok: false, error: error.message });
  }
};
