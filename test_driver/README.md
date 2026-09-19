# UI exploration pilot

Run Run-CCS-UI-Tests.cmd on this Windows machine (Flutter and Pixel_7_Pro AVD required).
The test installs a debug app in an Android emulator, never on a physical device.
The launcher sets CCS_UI_SANDBOX=1: application ID is com.example.ccs_app.uitest,
separate from the normal app; production Google Services configuration is not applied.
It disables emulator Wi-Fi/mobile data and enables airplane mode, rejecting active
default network routes (dummy0 is an Android non-network placeholder).
The emulator is left offline. The computer's network is not changed.

Current actions: text editing, scrolling, leaving and reopening actual screens,
random visible enabled buttons, switches and checkboxes. This is not an exhaustive
control inventory: custom gestures, menus and native dialogs need separate journeys.
The Section parameter selects spots, explore, profile, garage, settings, chats,
saved, submissions, notifications, friends or xp. The launcher menu also offers all.
All eleven screens were attempted in a three-action smoke run on 2026-09-05.
Saved, submissions and notifications passed that short run. Profile, chats, friends
and XP encountered missing Firebase fixtures, not confirmed production failures.
Spots and settings raised ListTile decoration assertions. Input-runner defects found
in explore and garage were corrected; both passed separate ten-action reruns.
Registration and a short pass are not proof of feature coverage.
Not covered: native photo picker, upload, submission, full navigation, auth, backend.
The test does not call the production main() bootstrap or initialize Firebase in Dart.
Dart HTTP requests are blocked. This is an isolated UI pilot, not full app E2E.
The harness uses a basic dark theme without the full production bootstrap; screenshots
are diagnostic evidence, not production visual-regression baselines.

Artifacts are in build/ui-explorer: screenshots, report.json, REPORT.md and launcher
logs. latest-summary.json describes only the most recent launcher invocation.
The report records the seed, executed actions and Flutter exceptions. A failed
assertion stops the run. A framework warning is a finding to review, not proof of
a production crash. Native process crashes may prevent Flutter screenshot capture;
retain launcher logs in that case. This pilot does not yet capture native crashes.

Repeat a seed or run a bounded series (stop on first failure):

```powershell
powershell -File test_driver/run-explorer.ps1 -Seed 1701 -Steps 40 -Rounds 10
powershell -File test_driver/run-explorer.ps1 -Section settings -Steps 40
powershell -File test_driver/run-explorer.ps1 -Section all -Steps 40
```

No background scheduler is installed. Repeated builds take longer than the actions.
Future work: isolate all native/backend endpoints and account state, then add photo
and database-backed journeys, replayable action files, native crash artifacts and
additional sections. Inspect gaps before treating a pass as application-wide health.
