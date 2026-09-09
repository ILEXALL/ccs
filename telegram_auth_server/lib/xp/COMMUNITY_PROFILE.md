# Community and XP profile

- The Community tab owns the Top 100 entry. Other shared app bars omit it.
- The XP card keeps its level/progress and three actions: achievements, rewards, history.
- `xp-sync` action `rewards` returns the current user's confirmed counts, awarded XP and pending counts. Amounts are derived from existing award evaluators. Viewing this guide does not award XP.
- `select_achievement` accepts `achievementId` (or null to remove). The authenticated user is the only target. A Firestore transaction verifies the original achievement award is confirmed before storing one catalogue item in `xp_featured_achievements/{uid}`.
- Only the featured catalogue item is shared; private XP stats and transaction rules are unchanged. Clients cannot write featured badges, including admins. Revoking the selected achievement through `adjustXp` clears the badge in the same transaction; restoring XP does not auto-select it.
- The catalogue still marks unimplemented achievement categories unavailable. This change does not activate them, alter XP amounts, or change weekly limits.

## Release

Deploy the updated Firestore rules and backend before distributing the new Flutter build. The backend must include `rewards.js`, the two new API actions, and the achievement revocation change. No new index or data migration is required. Existing profiles show no badge until their owner selects one. No production deployment is performed by local tests.

## Local checks

- Node: achievements, adjustments, workflows and existing XP matrix tests.
- Firestore emulator: reading featured badges, rejecting forged writes, preserving XP access and moderation checks.
- Flutter: three languages, selection failure/removal, reward retry, action order, real XP summary at 320/430px.
- Widget screenshots are synthetic fixtures, not production user balances.
