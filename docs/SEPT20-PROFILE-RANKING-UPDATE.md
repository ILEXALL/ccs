# Profile, ranking and startup update — 20 September 2026

Implemented against the current project files, preserving the existing GPS interval.

- Logout detaches authenticated screens before cleanup and allows cached Firestore streams to be subscribed to again. Best-effort network cleanup cannot indefinitely hold logout open.
- Event start/end labels wrap instead of truncating.
- Both ranking periods, search and pagination use the signed-in profile country, enforced on the backend. Profiles without a country do not receive a worldwide ranking.
- Native launch backgrounds are black; the Flutter logo fades in before the initial screen. Native splash and logout should also be checked on a physical device.
- Spot/event pin selection opens at the selected profile city. Existing selected coordinates are preserved.
- Profile setup/editing use country-first searchable city selection, with offline GeoNames coordinates. Data covers 55 supported countries, using cities500 populated places and administrative seats; it is not an exhaustive list of every settlement. Attribution is in assets/cities/ATTRIBUTION.txt. City assets total about 23 MB before package compression.

## What you need to do

1. From G:\FlutterProjects\ccs\telegram_auth_server, run `vercel --prod` for country-based rankings. The backend still has 12 API functions.
2. From G:\FlutterProjects\ccs, run `flutter pub get`, then your normal release build command (for example `flutter build apk --release`). Install the rebuilt app.
3. No additional Firestore rules/index deployment is required by these six changes. Previously pending changes from earlier updates are separate.

No production deployment or app build was performed.

## Verification

- 28 Flutter tests passed: profile location, ranking pagination and new stream/city/startup regressions.
- 190 offline backend tests passed, including country isolation, search and pagination.
- Device checks after installation: logout/login, full event dates, two accounts with different profile countries, city change followed by pin selection, and cold startup in light/dark system mode.
