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

## Activation and follow-up, 2026-09-21

Production backend is the Vercel project `ccs` (team `ccs-projects1`, root `telegram_auth_server`), alias `https://ccs-wine.vercel.app`. The older local `.vercel` binding names a different project: do not deploy using that binding. XP, leaderboard and GPS visits now use the same canonical backend in the client. The obsolete API-level spot-visit wrapper was removed; the existing rewrite routes visits to the validated community handler, keeping within the 12-function plan limit. Unauthenticated smoke requests to both routes return 401 and `X-CCS-Rewards-Version: weekly-live-v1`.

Only `app_config/xp` was inspected in production, with permission. XP, levels and achievements were enabled, all users allowed, weekly limit 3000, zone Europe/Riga. No configuration writes were made.

The composite `garage.first_car_full` task is retired at the user's request. It checked only the first garage car and required every field including tags; no new awards are generated and it is absent from the current catalog. Other first-car tasks total 175 XP. Existing ledger entries and previously earned XP remain intact.

The admin target picker loads immediately, searches while typing (300 ms debounce), and shows five approved, non-deleted spots/events per page with Show more. Search runs over the full eligible collection before pagination, ignores case and accents, and stale responses cannot overwrite a newer query. Pending/rejected places cannot be used for visit rewards. Dates explicitly describe the eligible visit interval in the device time zone.

Client package is 1.0.9 (5). Building an IPA alone does not update the installed app or publish it to TestFlight. Real-device authenticated GPS and actual TestFlight distribution remain separate from offline tests and unauthenticated production smoke checks.

Country badge radius correction: `visit_country` previously awarded from country GPS alone despite the 100 m requirement shown in the achievement screen. It now requires a current visit to an approved, accessible spot within the same 100 m radius, using `recordSpotVisit` for authoritative validation (including event dates, group membership, GPS freshness and accuracy). GPS with no nearby eligible spot returns `visit_required` without awarding country XP. Regression cases cover 99.6 m, 100.4 m, 500 m, no spots and restricted/expired targets. Existing country awards are not revoked. This is a server-side correction; existing clients calling the updated backend require no rebuild for it.
