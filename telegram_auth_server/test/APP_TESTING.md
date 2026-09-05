# CCS test sections

Open `Run-CCS-Tests.cmd` in the repository root and select a number.
Requires Node.js 22 or newer; no Firebase credentials or extra packages.

From the repository root:

```sh
node telegram_auth_server/test/run.cjs --list
node telegram_auth_server/test/run.cjs profiles
node telegram_auth_server/test/run.cjs all --report report.json
```

Sections: xp, profiles, spots, moderation, chats, access, notifications, all, emulator.
All means all available checks, not full app coverage. Shared test files execute
once. A failed test or runner error exits nonzero; zero passed tests are a failure.
Reports contain counts, raw output and untested areas. No scheduler is installed.

| Section | Current checks | Still needed |
| --- | --- | --- |
| XP | Rewards, levels, caps, rankings, opt-out | Rules, concurrency, device UI |
| Profiles | Own sync, other-user access | Editing, uploads, garage persistence |
| Spots | Pending/approved sync, author access | Creation, filters, deletion, review locks |
| Moderation | Staff-only forum pinning | Spot approval/rejection and locks |
| Chats | Member removal and permissions | Messaging, attachments, realtime updates |
| Access | Authentication required, HTTP methods | Real providers, tokens, database rules |
| Notifications | XP opt-out, duplicate prevention | Real push delivery and other types |

The fixture loads actual server handlers with a synthetic database and auth.
Transactions are sequential doubles, not Firebase emulator transactions. An approved
spot is seeded in the sync test; actual approval is not executed. Unrecognized
dependencies fail closed rather than initializing production services.

Add tagged scenarios to workflows.test.js or dedicated test files and register
them in run.cjs. Specify initial state, actor, actions and independent expected
outcomes. Denied actions must leave state unchanged. Keep coverage gaps visible.

Next: demo-project Firebase emulator tests for rules and concurrency, then Flutter
device integration tests for real UI journeys and all three languages. Never run
mutation scenarios against production. XP_ORACLE.md records current XP expectations.

## Firebase Emulator

Menu item 9 runs actual Firestore rules checks with a fresh local database.
Alternatively: `node telegram_auth_server/test/run.cjs emulator`.
The separate firebase.test.json uses project demo-ccs-tests and port 18080.
The production firebase.json and Firestore rules are not modified.
Emulators start and stop automatically. The first run downloads the emulator.
Requires Java (Android Studio JBR is detected on this computer), Firebase CLI and
the isolated test dependencies. Install them with `npm install --prefix telegram_auth_server/test`
from the repository root. Other computers need these prerequisites too.

Seven scenarios cover XP write protection, spot creation, authorship, moderation
region, active/expired review locks and competing approval/rejection writes.
Review locks are seeded; their backend acquisition is not tested yet. Authentication
contexts are simulated by rules-unit-testing, not a real sign-in provider.
The all command remains the quick offline suite; emulator is a separate slower run.
This is not device E2E and does not test real upload, notifications or XP award
transactions under contention. Some denied rules branches log expression-limit
errors in firestore-debug.log; success of negative tests alone cannot diagnose these.
