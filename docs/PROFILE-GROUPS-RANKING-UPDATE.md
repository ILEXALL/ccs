# Profile achievement, groups, map and ranking update

- Earned achievements offer Display on profile on your own board. Selection uses the existing server endpoint, which verifies ownership and confirmed status. One selected emblem appears beside the username in your profile and public profile. Another selection replaces it.
- The country directory includes public-style group chats as well as private groups. Existing joined chat rows remain available, and duplicates are suppressed. Nonmembers see directory metadata, never message previews or member identities; joining requires owner approval. Actual live records for Left Lane and СИЛОВИКИ were not inspected from these screenshots.
- Main map and creation maps now stop at zoom 3, approximately Europe-scale on a portrait phone, instead of zoom 0.
- Rankings reload when profile country changes. The app requires a matching country in the server response and refuses old global responses. The backend filters results, ranks, search and cursors using the authenticated profile country.

## Apply

Deploy Vercel production from telegram_auth_server, then rebuild and install the Flutter app. Deploy the current backend to the primary ccs-telegram-auth-server project: an older global leaderboard endpoint will now be rejected by the app. There are still 12 API functions. No new Firestore rules or indexes were added; the existing xp_featured_achievements read rules must already be live.

No app build or deployment performed. Validate both Android and iOS on device after installation, including changing Latvia to Estonia and replacing the displayed achievement.
