# CCS XP test oracle and scenario-generation brief

## Purpose and status

Use this document to generate reproducible tests of CCS XP. It is a tool-neutral
brief, not a verified Fable/FAM import format. No external AI service is required.
An oracle defines expected outcomes; a runner executes scenarios and compares them.
Do not use the production function under test to compute its own expected result.

Scope: profile, first garage car, approved permanent spots, XP totals, access,
notifications and leaderboards. Do not claim coverage of unrelated app features.

## Evidence and authority

User-confirmed requirements: tester-only rollout, 3000 XP weekly cap, no duplicate
one-time rewards, top 100 and weekly ranking, notification opt-out, three UI languages.
Reward amounts and content thresholds below are the current implementation baseline,
not an independently supplied product specification. Flag contradictions for review;
do not silently redefine expectations to make a failing test pass.

## Reward baseline

| Action | Expected XP | Condition |
| --- | ---: | --- |
| profile.avatar | 50 | Avatar URL or path present |
| profile.bio | 40 | Trimmed bio length at least 20 |
| profile.city | 30 | City present |
| profile.social | 30 | Instagram or Telegram present |
| profile.full | 100 | All four profile conditions met |
| garage.first_car | 50 | First car exists |
| garage.first_car_photo | 50 | At least one unique photo |
| garage.first_car_description | 50 | Trimmed description length at least 20 |
| garage.first_car_gallery | 25 | At least three unique photos |
| garage.first_car_full | 75 | Name, description, photo, build/use type and tag present |
| spot.approved | 50 | Approved permanent spot with author |
| spot.description | 15 | Same eligibility, trimmed description at least 20 |
| spot.photo | 25 | Same eligibility, at least one unique photo |
| spot.media_bundle | 10 | Same eligibility, three photos or a reel |

Full profile = 250 XP; full first car = 250 XP; full permanent spot = 100 XP.
Identical cover and gallery paths count as one photo, not two.

## Oracle invariants

- Award identity is user + action + object type + object ID + stage.
- Repeating a confirmed award does not increase totals or create another notification.
- An eligible new award applies min(requested XP, remaining weekly allowance).
- Weekly confirmed total stays between 0 and 3000 under the default configuration.
- A new Riga calendar week starts on Monday at local midnight, including DST changes.
- One-time rewards stay one-time across week changes.
- Level L starts at 25 * (L - 1)^2 XP, levels are bounded by 1 and 100.
- Missing/disabled rollout configuration denies access; non-testers cannot earn XP
  or request either leaderboard during the closed rollout.
- Explicit wildcard rollout permits active users. Pausing awards alone need not hide rankings.
- Deleted/banned users cannot earn XP; private profiles do not appear in rankings.
- Rankings sort eligible users by descending XP and return at most 100 entries.
- Weekly pagination must not omit a leader beyond document 1000 or 2000.
- Legacy/current week records for one user yield one ranking entry, not duplicate XP.
- Disabling XP notifications preserves the award and suppresses its notification.
- Clients cannot write XP totals or transactions directly (requires rules tests).

## Scenario layers

1. Fixtures: missing fields, blank text, duplicate media, legacy/current schema.
2. Condition matrices: eligibility, text boundaries, media count, alternate fields.
3. Stateful application tests: repeated requests, weekly limits, configuration changes.
4. Emulator integration: actual Firestore transactions/retries, rules and auth boundaries.
5. Device E2E: sign in, edit profile, moderate spot, inspect history/ranking, change
   language, opt out of notifications, restart app and confirm persistence.

Only layers 1-3 have local checks at this stage. In-memory doubles do not establish
that rules, concurrent writes, native plugins or real push delivery work.

## Baseline journey

Given an active enabled tester with 0 XP, an empty profile and sufficient allowance:
1. Add avatar, city, social account and a 20-character bio: total 250, level 4.
2. Repeat synchronization: total stays 250; no duplicate notification records.
3. Add a complete first car with three distinct photos: total 500, level 5.
4. Submit a pending permanent spot: total stays 500.
5. Approve it with a 20-character description and three photos: total 600, level 5.
6. Reapprove/synchronize the same spot: total stays 600.
7. Repeat the journey as a non-tester: no XP awards; leaderboard returns 403.

## Generator contract

Generate small named tests with scenario IDs, initial state, actions, expected state
and observed state. Exhaust finite boundary matrices before adding random sequences.
For randomized model-based tests, use an established library such as fast-check;
record seed and replay path and minimize failures into short regression scenarios.
Keep a stable regression set; new daily seeds supplement it, never replace it.
Do not label thousands of condition combinations as thousands of device E2E journeys.

Separate credentials-free unit checks from emulator tests. Emulator runners must
require a local emulator endpoint and a demo project ID before any writes. Device
tests must use a dedicated test environment and synthetic accounts. Do not target
production, send real notifications or upload project data to an external tool.

## Unresolved product decisions

- Should an award blocked by the weekly cap be recoverable next week?
- Should the unpaid remainder of a partially capped award be recoverable?
- When a previously approved spot is rejected/deleted, should XP be revoked?
- What validation proves a photo/social link is real rather than merely nonempty?
- What tie-break policy should apply when many users reach 3000 XP?

Keep these as decision-required cases. Do not assert an invented business rule.

## Execution and reporting

From the repository root, Node.js 22 or newer:

```sh
node --test --test-isolation=none telegram_auth_server/test/xp.test.js telegram_auth_server/test/xp-matrix.test.js
```

Report pass/fail counts, scenario combinations, seed when applicable, commit under
test, untested layers and failures with reproduction steps. Any failure exits nonzero.
No daily schedule is installed by this document. A later CI job can run the stable
suite per change and generated sequences nightly, with retained failure artifacts.

References:
- https://docs.flutter.dev/testing/overview
- https://fast-check.dev/docs/advanced/model-based-testing/
