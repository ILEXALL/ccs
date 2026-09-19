# XP adjustments: server foundation

Not deployed. No administration UI or automatic deletion integration is included.

Authenticated POST /api/xp-sync accepts action `adjust_xp`, transactionId,
requestId (a fresh ID per administrator decision), operation (`revoke` or `restore`),
reason, and expectedRevision (0 initially; use the returned revision subsequently).
Retry an uncertain request with exactly the same requestId and payload.

Only an active administrator can use this initial implementation. Self-adjustments
and adjustments of correction entries are rejected. Amount and recipient come from
the original server reward, not the request. Pending rewards cannot be corrected.
Stale revisions are rejected, including delayed revoke requests after restoration.

Each transaction atomically changes the total and level, updates the original
reward status, creates a signed correction in xp_transactions, and creates an
xp_admin_audit record with actor, reason, before/after values and result.
The existing default-deny Firestore rules disallow client access to the new audit
collection. Admin SDK access is still privileged; this is not tamper-proof storage
against project administrators. No audit read interface is implemented yet.

Weekly earning capacity (`confirmedXp`) is deliberately not refunded on revocation;
restoration does not consume it again. Weekly net ranking subtracts `revokedXp` from
that counter. Corrections affect the original reward week, not the current week.
The profile cache is updated only when its week matches the corrected week; new
awards retain the net calculation. Corrected canonical week documents override
legacy mirrors, including a net score of zero. Missing canonical weekly ledgers
require reconciliation before adjustment; no guessed counters are created.
Do not enable this endpoint as a complete moderation workflow yet.

Remaining work: moderator regional permissions, audit UI/API, localized correction
labels, handling pending rewards, server-authoritative deletion
reasons and the 30-day owner-deletion rule, batch spot corrections, and emulator
tests of concurrent transactions. Offline doubles test behavior, not Firestore
concurrency guarantees. Automatic award sync never restores a revoked reward.

Run test/xp-adjustments.test.js with the XP suite in test/run.cjs.
