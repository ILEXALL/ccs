const { escapeHtml, publicBaseUrl, telegramBotUsername } = require('../lib/telegram');

module.exports = async (request, response) => {
  try {
    const sessionId = String(request.query.sessionId ?? '');

    if (!sessionId) {
      response.status(400).send('Missing sessionId.');
      return;
    }

    const baseUrl = publicBaseUrl();
    const botUsername = telegramBotUsername();
    const authUrl = `${baseUrl}/api/telegram-callback?sessionId=${encodeURIComponent(sessionId)}`;

    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.setHeader('Cache-Control', 'no-store');
    response.status(200).send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CCS Telegram Login</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: #050507;
        color: white;
        font-family: Arial, sans-serif;
      }
      main {
        width: min(420px, calc(100vw - 32px));
        text-align: center;
      }
      h1 {
        color: #1565ff;
        letter-spacing: 0.16em;
      }
      p {
        color: rgba(255, 255, 255, 0.68);
        line-height: 1.45;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>CCS</h1>
      <p>Confirm Telegram login to continue.</p>
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="${escapeHtml(botUsername)}"
        data-size="large"
        data-auth-url="${escapeHtml(authUrl)}"
        data-request-access="write">
      </script>
    </main>
  </body>
</html>`);
  } catch (error) {
    response.status(500).send(error.message);
  }
};
