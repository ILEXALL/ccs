# Weekly and administrator rewards

Implemented locally; deployment and real-device GPS verification are still required.

## Rules

- Riga calendar weeks, starting Monday. Stable pseudorandom schedule from 2026-09-21, three tasks worth 150/200/250 XP. Uses 18 supported definitions from the planning catalogue; unsupported photo-contribution/helpful-answer tasks remain excluded. Adjacent metric repeats are minimized; the regression checks 520 weeks with no such repeats. Exact task IDs have three intervening weeks before reuse. Repeated location requests never reroll tasks.
- Seven distinct permanent spots per user/week can each award 300 XP. The same locations are eligible next week. Events use their existing 200 XP reward, not the permanent-spot reward. Lifetime achievements stay deduplicated independently.
- Server-validated GPS visits store daily evidence without coordinates. Distinct-day tasks require different places on different dates. Category tasks use the actual `categories` array and distinct places. Event combination tasks exclude events created by the visitor.
- Publication tasks use the original server XP transaction's approval/creation week and captured completeness. Legacy records without publication metadata do not retroactively satisfy weekly tasks.
- Completed tasks award automatically. These and per-week visit rewards are indivisible entitlements: when insufficient capacity remains, the full amount stays pending. Existing pending rewards are settled first at the next authenticated XP synchronization/rewards load, consuming that week's allowance. No midnight scheduler or promise of a push while the app is closed.
- Achievements retain their existing exemption from the 3000 XP ordinary weekly limit.

## Admin panel → Rewards

Only active administrators may list, search targets, create, or stop campaigns. Every API action rechecks the server role; moderators have no access. No client writes to the reward collections are allowed by the existing default-deny Firestore rules.

An admin selects an approved spot/event, enters a title, 1–3000 XP and start/end times (maximum 90-day active interval). Dates in the editor use the device time zone; stored values are UTC epoch milliseconds. The custom title is displayed as entered in all three app languages. Campaign dates must overlap an event's availability. A fixed ID makes retries idempotent; conditions cannot be modified after creation. Stop and create a new campaign for new conditions.

Each user earns the campaign once, after a fresh validated visit during its validity interval and after campaign creation. A visit before creation does not count. Access restrictions, event validity and group membership remain enforced. Claims snapshot the reward in the same transaction as the visit and survive campaign expiry/cancellation. Cancellation stops new claims. XP can be delayed by the weekly limit without losing the claim.

## Integration and rollout

New collections: `weekly_visit_records`, `admin_rewards`, `admin_reward_claims`. Server Admin SDK only. New queries use single-field indexes; the existing XP settlement indexes still apply. No additional API function is added: commands use the existing xp-sync endpoint, visits use spot-visit.

Deploy the backend before distributing the rebuilt Flutter app. Existing `app_config/xp` switches (`levels_enabled`, `xp_awards_enabled`, `enabledUserIds`, `achievements_enabled`) are respected; this change does not edit production configuration or bypass rollout restrictions. Old clients may suppress repeat GPS submissions for a session, so install the updated app for reliable weekly repeats.

Before rollout, verify on devices: fresh GPS at a selected spot, duplicate requests, next-week reuse, group-private event access, cancellation during attendance, and pending XP across the Riga Monday boundary. Offline tests verify logic with a transaction double, not Firestore concurrency or push delivery.

Forum/group activity rewards remain a separate proposal and are not enabled by this change.
