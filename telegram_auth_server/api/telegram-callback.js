const { admin, db } = require('../lib/firebase-admin');
const { escapeHtml, verifyTelegramLogin } = require('../lib/telegram');

module.exports = async (request, response) => {
  const sessionId = String(request.query.sessionId ?? '');

  try {
    if (!sessionId) {
      response.status(400).send('Missing sessionId.');
      return;
    }

    const sessionRef = db.collection('telegram_login_sessions').doc(sessionId);
    const sessionSnapshot = await sessionRef.get();

    if (!sessionSnapshot.exists) {
      response.status(404).send('Login session not found.');
      return;
    }

    if (!verifyTelegramLogin(request.query)) {
      await sessionRef.set({
        status: 'error',
        message: 'Telegram signature verification failed.',
        updatedAt: Date.now(),
      }, { merge: true });

      response.status(403).send('Telegram verification failed.');
      return;
    }

    const telegram = {
      id: String(request.query.id ?? ''),
      first_name: String(request.query.first_name ?? ''),
      last_name: String(request.query.last_name ?? ''),
      username: String(request.query.username ?? ''),
      photo_url: String(request.query.photo_url ?? ''),
      auth_date: String(request.query.auth_date ?? ''),
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

    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.status(200).send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CCS Telegram Login Complete</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: #050507;
        color: white;
        font-family: Arial, sans-serif;
        text-align: center;
      }
      h1 { color: #1565ff; }
      p { color: rgba(255, 255, 255, 0.72); }
    </style>
  </head>
  <body>
    <main>
      <h1>Telegram connected</h1>
      <p>You can return to CCS now.</p>
      <p>@${escapeHtml(telegram.username || telegram.id)}</p>
    </main>
  </body>
</html>`);
  } catch (error) {
    if (sessionId) {
      await db.collection('telegram_login_sessions').doc(sessionId).set({
        status: 'error',
        message: error.message,
        updatedAt: Date.now(),
      }, { merge: true });
    }

    response.status(500).send(error.message);
  }
};
