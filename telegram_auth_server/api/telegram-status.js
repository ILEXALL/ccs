const { db } = require('../lib/firebase-admin');

module.exports = async (request, response) => {
  try {
    const sessionId = String(request.query.sessionId ?? '');

    if (!sessionId) {
      response.status(400).json({ status: 'error', message: 'Missing sessionId.' });
      return;
    }

    const sessionRef = db.collection('telegram_login_sessions').doc(sessionId);
    const sessionSnapshot = await sessionRef.get();

    if (!sessionSnapshot.exists) {
      response.status(404).json({ status: 'error', message: 'Login session not found.' });
      return;
    }

    const data = sessionSnapshot.data();
    const ageMs = Date.now() - Number(data.createdAt ?? 0);

    if (data.status === 'pending' && ageMs > 10 * 60 * 1000) {
      await sessionRef.set({
        status: 'error',
        message: 'Telegram login session expired.',
        updatedAt: Date.now(),
      }, { merge: true });

      response.status(200).json({
        status: 'error',
        message: 'Telegram login session expired.',
      });
      return;
    }

    response.setHeader('Cache-Control', 'no-store');

    if (data.status === 'complete') {
      response.status(200).json({
        status: 'complete',
        firebaseToken: data.firebaseToken,
        telegram: data.telegram,
      });
      return;
    }

    if (data.status === 'error') {
      response.status(200).json({
        status: 'error',
        message: data.message || 'Telegram login failed.',
      });
      return;
    }

    response.status(200).json({ status: 'pending' });
  } catch (error) {
    response.status(500).json({ status: 'error', message: error.message });
  }
};
