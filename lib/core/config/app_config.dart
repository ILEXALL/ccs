// Paste the OAuth 2.0 Web Client ID from Firebase/Google Cloud here.
// It usually looks like: 325709324670-xxxxx.apps.googleusercontent.com
const googleServerClientId =
    '325709324670-cep9b3r2j2mmapmmuougmqai7umvlod6.apps.googleusercontent.com';

// Real Telegram login needs a small backend server.
// Keep a fallback here so login still works when one Vercel hostname
// has a temporary DNS/network problem for a specific user or carrier.
const telegramAuthBaseUrls = <String>[
  'https://ccs-wine.vercel.app',
  'https://ccs-telegram-auth-server.vercel.app',
];

const telegramAuthBaseUrl = 'https://ccs-wine.vercel.app';

const pushNotificationUrls = <String>[
  'https://ccs-telegram-auth-server.vercel.app/api/push-notification',
];

// Dedicated route for immediate friend live-location alerts. The server route
// derives the friend list, checks preferences, writes notification history,
// and sends an FCM notification payload for both Android and iOS.
const liveLocationPushNotificationUrls = <String>[
  // Use the backend project that contains api/live-location-notification.js.
  // Keep this single-host while testing so another endpoint cannot swallow the
  // request before it reaches the deployed route and its Vercel logs.
  'https://ccs-telegram-auth-server.vercel.app/api/live-location-notification',
];

const pushNotificationUrl = '$telegramAuthBaseUrl/api/push-notification';

const firestoreUsageUrl =
    'https://ccs-telegram-auth-server.vercel.app/api/firestore-usage';

// Moderation must use the project deployed from telegram_auth_server, not the
// legacy Telegram-login host (which can run an older moderation endpoint).
const moderationActionUrl =
    'https://ccs-telegram-auth-server.vercel.app/api/moderation-action';

// Assignments, progress and visit evidence must use the same deployed backend.
// A successful response from the legacy server can still be an inactive preview.
const xpSyncUrls = <String>['$telegramAuthBaseUrl/api/xp-sync'];

const xpLeaderboardUrls = <String>['$telegramAuthBaseUrl/api/xp-leaderboard'];

const spotVisitUrl = '$telegramAuthBaseUrl/api/spot-visit';

// Keep old builds on their original host during migration. New uploads must
// never fall back from this authenticated endpoint to the legacy service.
const r2PresignUploadUrl = '$telegramAuthBaseUrl/api/r2-presign-upload';

const int maxSpotGalleryPhotos = 4;

const Duration maxTemporarySpotDuration = Duration(hours: 12);

// TEST KILL SWITCH: disable repeating friend-location notification polling.
// Re-enable only after Firebase reads confirm this is not the overnight drain.
const bool friendLocationNotificationPollingEnabled = false;

const double minimumPermanentSpotDistanceMeters = 100;

const int maxGaragePhotos = 4;

const int r2SpotPhotoMaxLongSide = 1280;

const int r2AvatarPhotoMaxLongSide = 768;

const int r2GaragePhotoMaxLongSide = 1280;

const int r2JpegQuality = 76;

const int chatAttachmentTargetBytes = 260 * 1024;

const int chatAttachmentMaxBytes = 300 * 1024;

const int r2ChatAttachmentPhotoMaxLongSide = 1280;

const double garagePhotoAspectRatio = 1.45;
