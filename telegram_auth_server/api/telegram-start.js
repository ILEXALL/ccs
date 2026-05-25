const crypto = require('crypto');
const { db } = require('../lib/firebase-admin');
const { telegramBotUsername } = require('../lib/telegram');

module.exports = async (request, response) => {
  try {
    if (request.method !== 'GET' && request.method !== 'POST') {
      response.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const sessionId = crypto.randomBytes(18).toString('base64url');
    const botUsername = telegramBotUsername();

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
