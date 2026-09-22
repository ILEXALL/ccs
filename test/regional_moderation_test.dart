import 'package:ccs_app/features/auth/data/auth_state.dart'
    as app
    show currentUser;
import 'package:ccs_app/features/auth/models/app_user.dart' as app show AppUser;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    as app
    show
        currentUserCanManageProfileCountry,
        currentUserCanModerateCountry,
        moderationNotificationAllowed;
import 'package:ccs_app/features/spots/data/spot_ownership.dart'
    as app
    show canTransferSpotOwnership;
import 'package:ccs_app/shared/models/user_role.dart' as app show UserRole;

import 'package:flutter_test/flutter_test.dart';

app.AppUser actor(
  app.UserRole role, {
  Set<String> countries = const {},
  bool flagged = false,
}) => app.AppUser(
  uid: 'actor',
  name: 'Actor',
  username: 'actor',
  email: '',
  role: role,
  country: 'Latvia',
  city: 'Riga',
  moderatorCountryCodes: countries,
  globalChatModerator: flagged,
);

void main() {
  late app.AppUser previous;
  setUp(() {
    previous = app.currentUser;
  });
  tearDown(() {
    app.currentUser = previous;
  });

  test('moderation follows assignments rather than moderator home country', () {
    app.currentUser = actor(app.UserRole.moderator, countries: {'EE'});
    expect(app.currentUserCanModerateCountry('EE', community: true), isTrue);
    expect(app.currentUserCanModerateCountry('LV', community: true), isFalse);
    expect(app.currentUserCanManageProfileCountry('Estonia'), isTrue);
    expect(app.currentUserCanManageProfileCountry('Latvia'), isFalse);
    expect(
      app.canTransferSpotOwnership(app.currentUser, countryCode: 'EE'),
      isTrue,
    );
    expect(
      app.canTransferSpotOwnership(app.currentUser, countryCode: 'LV'),
      isFalse,
    );
  });
  test('global moderator flag requires explicit country assignments', () {
    app.currentUser = actor(app.UserRole.moderator, flagged: true);
    expect(app.currentUserCanModerateCountry('LV', community: true), isFalse);
    app.currentUser = actor(
      app.UserRole.user,
      flagged: true,
      countries: {'EE'},
    );
    expect(app.currentUserCanModerateCountry('EE', community: true), isTrue);
    expect(app.currentUserCanManageProfileCountry('Estonia'), isFalse);
  });
  test('moderators see review alerts only for assigned countries', () {
    app.currentUser = actor(app.UserRole.moderator, countries: {'EE'});
    for (final type in [
      'spot_pending_review',
      'forum_topic_pending',
      'global_chat_admin',
      'user_report_new',
    ]) {
      expect(
        app.moderationNotificationAllowed({'type': type, 'countryCode': 'EE'}),
        isTrue,
      );
      expect(
        app.moderationNotificationAllowed({
          'type': type,
          'data': {'countryCode': 'LV'},
        }),
        isFalse,
      );
      expect(app.moderationNotificationAllowed({'type': type}), isFalse);
    }
    expect(
      app.moderationNotificationAllowed({
        'type': 'moderator_user_banned',
        'countryCode': 'EE',
      }),
      isFalse,
    );
  });
  test('admins retain all-country moderation and alerts', () {
    app.currentUser = actor(app.UserRole.admin);
    for (final code in ['EE', 'LV', 'DE', '']) {
      expect(app.currentUserCanModerateCountry(code, community: true), isTrue);
      expect(
        app.moderationNotificationAllowed({
          'type': 'moderator_user_banned',
          'countryCode': code,
        }),
        isTrue,
      );
    }
  });
}
