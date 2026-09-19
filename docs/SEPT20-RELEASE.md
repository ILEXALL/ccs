# September 20 app and backend update

The current project files were used as the base. Nothing was built or deployed.

## Publish in this order

1. From `G:\FlutterProjects\ccs`, deploy indexes:
   `firebase deploy --only firestore:indexes --project ccsv1-63537`
   Wait until the three notification indexes are enabled. Keep unrelated existing indexes if prompted to delete them.
2. From `G:\FlutterProjects\ccs\telegram_auth_server`, deploy Vercel production:
   `vercel --prod`
   Confirm Ready and the production alias before distributing the app.
3. Build and distribute the Flutter app using your normal process.

This change adds no Firestore rules requirements. The new location-integrity documents are server-only under the existing default-deny rule. Existing rules changes from earlier work are separate.

The backend still has 12 API entry files. New helpers and handlers reuse existing functions; no extra Vercel function was added.

## Behavior

- Admin group country picker uses the enabled community countries, excluding regional restrictions.
- Plus menu offers Add Spot, Add Event, Add Private Event. Private event creation selects groups without a public/group switch. Events exclude Store, Photo, Service, Detailing, Wash, Activity, Food, Scrap.
- Event attendance requires a fresh, non-mocked GPS fix within 100 metres while the approved event is active. Private events additionally require actual group membership. Attendance awards 200 XP once per user/event; attendance milestones are 1/5/25/50/100 for 25/100/200/350/600 bonus XP. Normal weekly XP limits still apply; attendance uses the existing one-time pending-award behavior at the cap. Historical visits are not automatically reclassified as event attendance.
- Live-location upload interval remains **60 seconds**. Poor fixes above 50m reported uncertainty, mock positions, stale samples and out-of-order Android background samples are rejected. The original GPS timestamp accompanies uploads. Moving users can still lag between uploads; this does not promise exact real-time positioning.
- The server rejects reported mock GPS and implausible travel (over 5km at over 400m/s between recent checks). It saves a private last sample, flags all active admins by bell/push, and limits alerts to once per user per 24 hours. Poor accuracy alone produces no accusation. Client coordinates can still be forged by a modified client; these are review signals, not proof, and do not automatically ban users.
- Bell notifications include XP reasons and achievement unlocks. New foreground rewards show a bottom banner, and level changes show a central animation with level.mp3. Bell audio uses bell.mp3; iOS remote notifications use a PCM WAV conversion of the supplied bell audio. Notification preferences and OS permission/settings apply.
- Badges use server unread totals in push payloads, plus the live app unread count while open. Android launcher controls whether the result is a number or a dot. The app cannot force every launcher to display a numeric badge.
- Ranking search starts at two characters, matches username or display name and loads search candidates in larger batches to avoid the previous per-ten-users round trips.

## Verify after your build/deployment

- Test a private event with a member and non-member; ensure it cannot be published publicly from that form.
- Attend an active event, repeat the GPS check, then attend a second event. Verify one 200 XP transaction per event and cumulative achievement progress.
- Check the XP reason, level animation, foreground bell sound, background sound and home-screen badge on your phones. Native Android/iOS compilation and device behavior were not tested because no app build was requested.
- Test real GPS in the foreground and background without changing the 60-second interval. A stale/inaccurate marker should not be presented as a fresh fix.

Validation: backend offline suite 188 passed; creation/ranking/reward feedback widget tests 15 passed; Dart static analysis has no errors (existing warnings/info remain). Security-rule emulator and physical-device delivery were not run for this update.
