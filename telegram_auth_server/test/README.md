# Local XP audit

Run from the repository root with Node.js 22 or newer:

```sh
node --test --test-isolation=none telegram_auth_server/test/xp.test.js
```

The suite executes the real XP modules and leaderboard handler with an in-memory
database and authentication double. It does not initialize Firebase, read account
credentials or contact production. No additional packages are required.

Regression checks cover the corrected leaderboard behavior:

- Weekly leaderboard must include a high scorer beyond the first 1000 document IDs.
- During the tester-only rollout, leaderboard requests from non-testers must be denied.
- Legacy weekly records are paginated and deduplicated against current records.
- Hidden leaders do not prevent filling the weekly top 100 from subsequent candidates.

The second check encodes the current private-rollout requirement, not a restriction
on a future public leaderboard.

These checks do not establish correctness of Firestore Security Rules, transaction
conflicts/retries, actual push delivery, UI translations or deployed code. Those need
emulator integration tests and device checks. The database double only models the
operations used here, and transactions in these tests run sequentially.
