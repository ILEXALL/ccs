# Achievements integration status

Local implementation only. No production flag or deployment was changed.
The profile opens an authenticated catalog through xp-sync action `achievements`.
The server owns thresholds, reward amounts and progress; the request cannot supply
counters, user IDs, XP amounts, country claims or unlocks.

The agreed catalog includes spots, visits, organized meets, active topics, CCS
membership, moderator service, confirmed reports, group ownership and country badges.
There are no verified-like achievements. Existing artwork covers 27 EU countries;
this is not a global country catalog. Country rewards remain disabled.

Implemented evidence collectors: approved permanent spots owned by the account,
and completed membership months from Firebase Auth creationTime. Membership month
anniversaries currently use UTC, with end-of-month clamping, not a daily scheduler.
The endpoint checks progress on opening or refreshing the achievements screen.
It does not run continuously or while the app is closed.

Awards additionally require app_config/xp.achievements_enabled = true, plus the
existing XP flags and tester allowlist. The new optional boolean is included in
firestore.rules validation. No user should be asked to enable it before release review.
XP transactions carry action achievement.unlock with objectId category.threshold;
they use the existing once-only transaction ID and notification flow. New achievement
awards bypass the ordinary weekly cap and are recorded in achievementBonusXp;
confirmedXp and weeklyXp still include them for ranking. Historical confirmed
awards are not reclassified automatically. See docs/XP_REVIEW_2026-09-13.md.
Pending badges indicate XP waiting; confirmed badges indicate credited XP. Revoked
awards cannot be automatically reissued. Deletion-driven achievement revocation is
not implemented, and historical counts cannot be reconstructed from deleted spots.

Not yet wired: server-validated check-ins and foreign-country determination,
anti-spoofing, approved report outcome ledger and deduplication, continuous monthly
group-membership history, moderator appointment intervals, completed meet evidence,
active-topic evidence. These categories are explicitly unavailable in the UI rather
than falsely awarding from untrusted or incomplete current state. Also not yet wired:
three pinned favorites, public profile badges and automatic background evaluation.

Art: 43 distinct SHA-256 files imported unchanged from the supplied ZIP. Opaque
checkerboard backgrounds are hidden by display clipping; files are not transparent
masters. Moderator uses the exact admin_panel_settings_rounded glyph from the app,
without a circle. Reports use report_outlined; group ownership uses groups. Meets
use directions_car and visits route to avoid category collisions. New glyph badges
are native UI graphics, not finished metallic raster illustrations. Stage labels
differentiate tiers; five-stage categories still need a fifth custom metallic asset.
These are remaining design tasks, not completed image generation.

Tests: achievements.test.js covers catalog uniqueness, languages, source evidence,
flags, cap/pending and duplicate protection. achievements_screen_test.dart verifies
phone layouts in EN/RU/LV using synthetic data and saves diagnostic screenshots.
No real account or production Firebase is accessed by these tests.
