# Map and launch follow-up

This update supersedes the city-selection/profile-city-map and animated-splash parts of SEPT20-PROFILE-RANKING-UPDATE.md.

- Country is selected from a dropdown; only city is typed manually. Country values remain normalized for rankings.
- Both maps request a current GPS fix. Denied permission, disabled location or failed lookup uses zoom 0 centred on the extent of accessible loaded spots (0,0 if none). Existing pins and intentional map movement take precedence. The live-location upload interval is unchanged.
- Startup displays a static logo against black.
- Initial notification snapshots and records created before the listener starts cannot trigger reward/bell feedback. Delayed foreground pushes sent before app launch are suppressed, including on iOS. Notification history and unread state are preserved; genuinely new notifications still work.

Only rebuild/install the app for this follow-up. No new backend, rules or index deployment. Nothing was built or deployed here.

Verification: 30 Flutter regression tests passed. Test location permission granted/denied, cold launch with existing unread notifications, and a newly received notification on a physical device. Native iOS changes require an iOS build/device check.
