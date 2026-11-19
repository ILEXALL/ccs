# Mobile updates — 19 November 2026

## Current completion status

The latest follow-up is complete in the actual project. Capsule (choice 7) is applied to both map renderers with event proximity clustering, count badges, zoom expansion and a selectable event list at coincident locations or the zoom limit. Spot/event comments now have persisted emoji reactions through long-press, using the existing emoji picker and badges. The older limitation and preview-only notes below are historical and superseded.

**Required user actions:** deploy the updated Firestore rules from `G:\FlutterProjects\ccs` with `firebase deploy --only firestore:rules --project ccsv1-63537`, then build/distribute the app. Firestore rules were not deployed by the agent. No index deployment or data migration is needed. Vercel is already successfully deployed; these additional changes need no Vercel redeployment.

Actual widget preview: `G:\Codex\Temp\ccs-event-marker-concepts\capsule-implemented.png` (dark/light, individual time, grouped count, 128px and 80px widths). Production PNG/SVG assets are in `assets/globe/`, with no runtime references to temporary files.

Reaction storage uses `spot_reviews/{id}.reactions[uid]`, atomically changing only the signed-in user's field. The UI watches persisted changes, supports change/removal, and invalidates stale session pages after writes. Rules require active membership/access to the spot; deny other-user reaction changes, unrelated field edits, invalid values, and pre-seeded reactions on new comments. Existing reply-to-author composition preserves drafts. No threaded-reply schema was needed.

Event grouping uses connected components of overlapping screen-space rectangles after existing visibility filters. It recomputes on map movement/zoom; groups contain every member, show a count instead of a misleading time, and split with zoom. Individual times use the viewer's local timezone. Ordinary spots and existing people clustering stay separate. MapLibre marker assets switch with dark/light style. Follow-only tilt and whole-bubble long-press remain implemented.

Validation: 67 map Node checks, 4 local Firestore emulator security scenarios, and 14 focused Flutter tests passed. Targeted analysis reports no errors/warnings (existing informational brace lints remain). No mobile build/package/archive or real SOS test notifications were performed.

## Earlier implementation history

## Behavior and compatibility

1. Event schedules retain the stored absolute instant (Firestore Timestamp / epoch milliseconds). Create/edit pickers use the device timezone and now say so. Shared date/time formatters normalize UTC arguments to the viewer's local timezone, including that device's DST rules. Generated forum event descriptions previously froze the creator's wall-clock text; they now rebuild the schedule from the existing structured timestamps when viewed, including English/Russian/Latvian legacy suffixes. No country-to-offset assumptions and no timestamp migration. Records with an incorrectly recorded historical instant cannot safely be corrected without knowing the original intended timezone; they are deliberately not shifted.
2. At 100 km/h, follow zoom now shows 3x the ground distance of low-speed view (previously 2x). Below 30 km/h the base scale stays unchanged; scale is capped at 5x. MapLibre retains smooth zoom and uses true 45-degree pitch while following. The Flutter Map fallback also gets speed zoom but remains 2D because its camera has no pitch. Manual browsing and route previews retain their existing behavior.
3. CCS Light uses its dark category artwork for event markers, dark event-time text, and a thin white halo. Dark-map styling is retained. Light edge beacons also use dark artwork.
4. Event creation says “Create event” for both regular and staff creators; moderation rules are unchanged. Permanent-spot labels are retained. New labels are translated into Russian and Latvian.
5. Capture eligibility is 40 metres on the client and authoritative server, including nearby custom tasks and country achievement evidence. Five-minute dwell, accuracy validation, and separate friend-arrival/presence radii are unchanged. Rewards/achievement help text is updated.
6. New SOS sends an authenticated `sos_created` event to the existing push endpoint. The server loads the owner's active report, resolves recipients from fresh (at most 5 minutes old), unexpired `live_locations`, applies a geodesic 10 km boundary, pages all matching locations, and dispatches in groups of 20. Sender, expired, invalid, future and mocked locations are excluded. Existing user eligibility, private FCM tokens and durable per-recipient delivery claims apply. The delivery key includes report creation time, so retries do not duplicate pushes and a later SOS can notify again. `sosNotifications` defaults to enabled; an explicit stored false is respected. Recent own reports retry on map synchronization; the existing HTTP sender retries failed attempts. Notification taps can focus the report coordinates.
   - Coverage limitation: users without fresh shared location data cannot be classified as nearby. No new background tracking was introduced. Push permission and usable FCM tokens are still required. This is client-requested delivery, not a new Firestore trigger: a client killed immediately after saving its SOS may require reconnecting within the 5-minute dispatch window. Production-wide guaranteed delivery would require a durable server trigger/outbox and a separately agreed location-consent strategy.
7. Spot-review cards collapse photos, map links, description and extra metadata under “Photos, map and details.” Name, status and approve/reject controls remain available. Normal 360px-wide collapsed cards test at no more than 210px high; roughly three fit on a typical phone depending on toolbar size and text scaling. All existing details, editing and rejection reasons are retained.
8. The foreground message banner checks the currently visible chat route. Covered/stacked chats do not suppress other chat notifications; disposing a conversation removes its registration. Entering a conversation dismisses an existing banner only for that chat. Existing global-chat suppression remains.
9. Direct/group chat, global chat and forum reply menu targets are 48x48 pixels. Small chat bubbles have a sensible minimum size. Tap/long-press, link taps, photos and reactions remain available. A failed/slow moderation lookup no longer prevents the direct/group chat reply/reaction menu from opening; server authorization remains authoritative.
10. Forum list/category/search filtering hides topics after exactly 30 elapsed days without activity, using the later of `lastReplyAt` and `createdAt`; existing minute timers update visibility. Replies already update `lastReplyAt`, so a new reply restores feed visibility on refresh. Legacy topic fetches no longer hold stale activity for an entire session. This is reversible feed hiding, not deletion: direct links and replies remain usable. Existing event expiry and access rules still apply. Records with neither activity nor creation timestamps remain visible rather than guessing their age. No scheduler, rules change or data migration is required; older app releases keep their old feed behavior.
11. Event/spot detail views, map and explore cards, and moderation descriptions use the existing link-aware widget (HTTP(S), www and bare-domain links, external browser launch, punctuation handling). Forum descriptions already used this widget.

## Deployment and device checks

- Deploy the existing `telegram_auth_server` service with the changed push endpoint and visit/task radius code before distributing the updated app. Keep its existing Firebase Admin/FCM configuration. No production deployment was performed here.
- Build/distribute updated mobile clients to activate the UI, forum feed policy and SOS client dispatch. No new package dependency, Firestore rule or composite index was introduced; SOS uses the standard single-field `updatedAt` query index.
- On staging/test accounts only, verify SOS foreground/background delivery, retries and notification tap routing with devices inside/outside 10 km. Do not use real public SOS reports for QA.
- Verify the same event on devices in different timezones, including summer/winter dates and edit/save round trips. Check main map pitch/zoom with simulated GPS, CCS Light contrast, photos/links, and large-text review layouts on Android/iOS.
- Undated forum legacy records can receive a reviewed timestamp backfill later if strict archival of those records is desired. Do not invent event timezone corrections from country names.

## Validation

- 28 focused Flutter tests passed: requested updates, message targets, review cards, event dates/details, foreground push policy, weekly rewards, live spot details, creation menu and trusted event time.
- Final six-test Flutter follow-up also passed, covering the updated legacy formatter and real fallback-map driving camera.
- 87 focused Node tests passed: map renderer/beacons/frame scheduling, SOS authorization/distance/pagination/deduplication, spot visits/dwell, nearby rewards and existing spot push dispatch. Two additional country-achievement radius/access tests passed.
- Dart analysis of app code and the new policy test reported no errors or warnings (existing informational lints remain). Full-project analysis also reports six existing test warnings; it is not a clean lint baseline.
- Broader checks exposed three unchanged-baseline failures, reproduced with original source restored temporarily: group upcoming-card test expects a “Group” label; old follow-exit test expects north reset although existing browsing preserves bearing; country-achievement test expects 75 XP but existing code yields 125. These unrelated behaviors were preserved.
- `git diff --check` passes. No production notifications, deployments or releases were sent.

## Applied directly to the actual project

All 45 task files were transferred and content-verified in `G:\FlutterProjects\ccs` without overwriting unrelated local work. The actual project then passed the same 28 focused Flutter tests, 89 Node checks and targeted Dart analysis. No app build, packaging, deployment or production notification was performed. `AGENTS.md` records direct-project work, no copies/backups/worktrees, and never building the app for the user.

The task checkout at `C:\Users\buzzie114\.codex\worktrees\fee9\ccs` was emptied and its Git worktree registration/metadata removed. Its empty directory remains locked by another process. Task temporary files were removed except `G:\Codex\Temp\ccs-validation\adb.log`, also held open by another process. No archive snapshot or replacement project copy was created. Existing video artifacts remain in the actual project.

Current required user actions: choose a marker concept, then build the app after any chosen design is implemented. The backend deployment succeeded in the retry documented below. Firestore rules/index deployment is not required for these changes.

## Authorized Vercel attempt — 19 November 2026

The user authorized deploying the backend (not building the mobile app). The old nested `.vercel/project.json` references an inaccessible project. The actual repository root is now correctly linked to existing team `ccs-projects1`, project `ccs` (`prj_0JHXarM8RMHLWpAvXkjHbUK20hoa`), whose configured root directory is `telegram_auth_server` and production alias is `https://ccs-wine.vercel.app`.

Deployment `dpl_5md37kHKd7EjumR7dCKqG6KQjoQm` / `https://ccs-eljr8a6c5-ccs-projects1.vercel.app` reached terminal state `BLOCKED`, with `TEAM_ACCESS_REQUIRED`: the commit author does not have permission to create deployments for this project. Production alias assignment did not occur. No permissions, commit authors, environment secrets or production rules were modified. The temporary client routing adjustment was reverted because deployment did not succeed. No mobile build or real SOS test notification was performed.

Next required action: resolve the commit-author deployment permission in Vercel, then retry backend production deployment from the repository root. The push endpoint must be aligned with the successfully deployed project before the user builds the app; the old notification hostname responds but is not inspectable through this team's current linkage. No Firestore rules deployment is required.


## Completed follow-up and successful production retry — 19 November 2026

This section supersedes the earlier blocked deployment and pending-deployment notes above.

- Production deployment `dpl_9Y2yVJZoqzUdSKxrWbKonpMbA7c6` is READY; alias assignment succeeded. `https://ccs-wine.vercel.app` now resolves to `https://ccs-5uexj6teh-ccs-projects1.vercel.app`. Deployment ran from the actual repository root, using the existing project's `telegram_auth_server` root-directory configuration. The app push endpoint now uses this production host. Safe unauthenticated probes returned 401 for push and 405 for visit/XP mutation routes. No real SOS notifications or authenticated test mutations were sent.
- MapLibre immediately stops follow animation and resets pitch to zero on manual pan/zoom/rotate/pitch input. Queued camera updates and continued pitch gestures cannot restore tilt. Explicitly resuming Follow restores 45 degrees. Non-follow camera packets always use pitch zero.
- Removed per-bubble three-dot controls from direct/group chat, global chat and forum replies. The entire bubble has a minimum 48px hit area and supports long-press actions. Child link/media/reaction taps and scrolling remain available. Direct/group actions open immediately while moderator permission resolves asynchronously.
- Spot/event comment cards use the same long-press interaction for reply-to-author composition, copy, edit and delete where permitted. Reply preserves an existing composer draft. These review records do not currently support emoji reactions or persisted reply threads; no new reaction schema or Firestore rules were invented.
- Marker concepts are previews only; none of these ten designs was applied. The repository supplies raster CCS branding but no reusable brand font, so EVENT lettering is custom vector artwork matched to its broad italic appearance. Each concept shows dark/light schematic maps at 128px width and enlarged scale.
- Preview directory: `G:\Codex\Temp\ccs-event-marker-concepts`. Full sheet: `event-marker-contact-sheet.png`; split sheets: `event-marker-concepts-01-06.png` and `event-marker-concepts-07-10.png`; editable SVG and `index.html` are included. Concepts: 01 Apex, 02 Halo, 03 Splitline, 04 Ticket, 05 Pace, 06 Signal, 07 Capsule, 08 Monolith, 09 Outline, 10 Flag.
- Follow-up validation: 62 map Node tests and 10 focused Flutter tests passed, including own/other/reply/link/short bubbles, media taps, long presses, drag cancellation, live detail updates and forum photo navigation. Targeted Dart analysis has no errors or warnings; three existing informational brace lints remain.

Remaining user actions: select marker design 1–10; build/distribute the mobile app after the selected design is implemented. No additional backend or Firestore rules/index deployment is needed for these changes. No mobile build/package/archive was performed.


## Startup region regression investigation

Confirmed source failure path: `loadCurrentFirebaseUser` previously called `saveFirebaseUser` during saved-login restoration. Any unrelated profile-write failure was swallowed as null, while `CCSApp` still selected MainScreen from Firebase auth/remember-me state. This could present the region form with the empty fallback AppUser, whose UID check then rejected every save. The screenshot and generic error alone do not prove which underlying failure occurred on the user's device.

Existing-profile restoration now reads the server profile without rewriting it, retains device/account checks, restores settings/garage, and verifies account identity after awaits. An incomplete/unloaded region gate explicitly reloads the profile before asking for missing fields; failed loads offer retry/sign-out instead of a false empty form. Region saves use a transaction (fail offline rather than queue indefinitely), have a bounded wait, preserve form drafts on errors, distinguish permission/session failures, and offer reload/sign-out. Country-filter initialization no longer blocks an acknowledged region save. A successful retry restarts the profile watcher if bootstrap skipped it.

Validation: 16 focused region/location Flutter tests passed, including loaded existing region, failed-load retry, real country-dropdown selection, permission-denied draft retry, and stalled-save timeout. Three local Firestore scenarios passed: ordinary new/existing owners can save; foreign/banned/role-escalation writes are denied; legacy profiles containing public email/token fields are rejected by the existing strict rules. That last condition is a verified rules behavior, not a confirmed diagnosis of this user's production record. The existing private-profile migration must be reviewed/authorized if such a record is confirmed; no production profiles, rules, permissions or services were changed here.

This fix requires the user to build/distribute the app. It introduces no additional rules change or Vercel deployment. The separately requested comment-reaction rules remain pending unless the user has deployed them; their deployment status is not assumed. A production-data audit/migration was not authorized and was not performed.


## Manual zoom and marker-scale regression fix (latest)

Reproduced using the actual bundled MapLibre in a local headless Chromium browser with two-finger CDP touch input. Replaying the old stop/jumpTo callbacks reduced a pinch from zoom 14 to only ~14.14; corrected handlers reach ~15.4 and zoom out normally. The gesture-start camera mutations and reentrant pitch reset were interrupting MapLibre's own gesture processing.

Manual gesture handlers now only leave follow mode. They never stop/jump/ease the camera during the gesture. Once touch/inertia ends, a pitch-only 320ms smoothstep ease levels the map without setting zoom, center or bearing. Explicit Follow eases pitch to 45 over 450ms using the existing render loop. Stale motion/native camera packets cannot restore follow or overwrite manual zoom. Real browser checks verify zoom in/out, leaving Follow, intermediate tilt values in both directions, retained bearing, and stale-packet rejection.

Capsule uses the same MapLibre spot sizing curve: ~30.4px width at zoom 11.25, growing to 65px at zoom 16. Below 11.25 it becomes a simple #1457ef blue dot using the regular spot-dot size curve (about 3.6px at zoom 6, up to ~8.3px before the threshold). Individual local times appear only from zoom 14; cluster counts remain compact at all zooms. Visual size and the minimum 44px touch target are separate. Cluster expansion and coincident/max-zoom selection lists are retained. Flutter Map uses the same event metrics and dot color. Prior 80–128px Capsule sizing is superseded.

Validation: 68 Node map tests, 16 focused Flutter tests, clean targeted Dart analysis, and the real-browser gesture/marker integration pass. Updated widget preview: `G:\Codex\Temp\ccs-event-marker-concepts\capsule-scaled.png`. No mobile build or deployment was performed. Required user action for this fix: build the app, then confirm gestures on the physical Android device; headless Chromium does not substitute for device QA. No backend/rules deployment is needed for this map fix. Earlier comment-reaction rules remain a separate release action if not already deployed.


## Follow speed display, pitched beacons, and event dates (latest)

Offscreen beacon arrows now project a short ground probe toward the destination instead of taking the direction of its distant perspective projection. This prevents the 180-degree inversion when the destination is behind the pitched camera plane. Existing edge placement, selection and fading remain. Real bundled-MapLibre browser checks cover 192 cardinal/intercardinal, bearing, pitch and longitude-wrap combinations, including 36 reproduced far-projection inversions. All directions pass; pinch zoom and smooth Follow transitions still pass.

Individual detailed event markers now show local DD.MM and HH:mm on two compact lines. Selection lists show DD.MM.YYYY and local time. The artwork remains 65px at zoom 16, with the same far-zoom blue dots and minimum 44px touch targets. Every multi-event marker opens its complete selectable member list immediately, including nearby clusters; taps never zoom to expand. Automatic grouping still responds to manual zoom. Both MapLibre and Flutter fallback are updated. The earlier zoom-on-cluster-tap behavior is superseded. Rendered widget preview: G:\Codex\Temp\ccs-event-marker-concepts\capsule-date-time.png.

Follow has a bottom road-limit/current-GPS-speed display. Current speed uses the raw GPS sample, never predicted motion, in km/h. Unknown, mocked, older-than-five-second, inaccurate position (>25m) or inaccurate speed (>2m/s) measurements display a dash. An applicable-limit model rejects expired/unverified/ambiguous limits before any overspeed highlight. The road limit intentionally remains unavailable: no provider adapter, API key, backend endpoint or external GPS transfer is enabled.

HERE integration is on hold because the user does not want card/payment signup. Automatic approval review also rejected the proposed API implementation pending explicit permission to send precise recent GPS coordinates/timestamps/speed/heading to HERE. That rejected command made no backend changes. A no-card source and hosting/coverage approach remain to be selected; Europe and Russia completeness is not asserted. Do not redeploy the backend for this partial speed display.

Validation: 70 Node map tests, 12 focused Flutter speed/event/date tests, and real headless browser gesture/marker/direction checks passed. Focused changed model/widget/event-controller analysis is clean; broader pre-existing map screen/navigation informational brace lints remain, with no errors or warnings. git diff --check passes. No mobile build, production deployment, paid signup or large dataset download was performed. User action: build the app and check Follow, gestures, beacons and event lists on a physical device. These changes require no backend or Firestore deployment; earlier comment-reaction rules are a separate pending action only if not already deployed. Live road limits remain unfinished pending provider choice and authorized integration.


## TomTom speed-limit integration (supersedes provider-on-hold status)

The user explicitly authorized evaluating TomTom and sending recent GPS samples through CCS's backend to TomTom. Implemented the legacy Snap to Roads API (TomTom Maps, not Orbis) through authenticated /api/road-speed-limit. TOMTOM_API_KEY stays server-side. The app now connects Follow's limit/overspeed display to validated road matches. Fresh raw GPS speed remains independent. Recent trace/headings/times, road confidence, snap displacement and travel direction gate acceptance; only supported Maximum limits are shown, with no national defaults or average-speed substitution. Limits expire and clear on movement/turns, bad GPS, missing data or provider errors. Requests cancel on Follow exit/background/hidden map; duplicate suppression, timeouts, backoff and durable per-user/global/daily/monthly quotas are in place. No precise trace is written to Firestore or application logs.

Current verified public pricing lists 2,500 free Snap-to-Roads requests per month on no-card Freemium, roughly 3.47 hours at the maximum five-second request cadence across all drivers. User's dashboard reportedly lists Snap to Roads access, but no live API response has been tested. Complete speed-limit coverage across Europe and the whole of Russia remains unverified. Provider-side data updates are consumed without rebuilding; physical-sign-to-provider update latency and weather/temporary-sign completeness are not guaranteed. Conservative 10m movement invalidation can produce gaps between limit readings while driving.

Setup and limitations: telegram_auth_server/ROAD_SPEED_LIMITS.md. Pending privacy disclosure was appended to docs/PRIVACY-POLICY-PUBLICATION-UPDATE.txt; it has not been publicly published. Remaining actions: configure TOMTOM_API_KEY in Vercel, publish/review the disclosure, redeploy the backend, build the app, then perform live road/device and regional coverage validation. No app build, production deployment, signup purchase or paid plan was performed. No new Firestore rules/index deployment is needed for this feature. Earlier comment-reaction rules remain a separate action if not already deployed.


## TomTom backend production deployment — 19 November 2026

Explicit user authorization received after TOMTOM_API_KEY was saved as a Production secret. Verified secret metadata only, correct ccs project/root telegram_auth_server and ccs-projects1 scope. Focused seven backend tests, syntax checks and diff whitespace checks passed before deployment. Deployed dpl_GLP3xvtybY1tzvQLYaxUNYeUhrMN; Vercel reports Ready and production alias https://ccs-wine.vercel.app points to https://ccs-70edhbefs-ccs-projects1.vercel.app.

Safe production probes: GET /api/road-speed-limit returns 405; POST without a token and with an invalid token return 401; responses carry Cache-Control: no-store. No authenticated CCS token was available, so a successful TomTom lookup, key validity at the provider, and regional data coverage are not verified. No authentication bypass/debug exposure was added, no secret value was retrieved/printed, and no real movement trace or notification was sent. No mobile build or Firestore rules deployment occurred.

Remaining: user builds the app and checks Follow on-device with a signed-in account; publish/review the prepared privacy paragraph separately on the existing Google Sites privacy page. That page is not hosted by this Vercel deployment and was not changed here. Europe/whole-Russia speed-limit completeness and physical-sign update latency remain unproven.
