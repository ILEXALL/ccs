import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

app.AppUser actor(app.UserRole role, {bool banned = false}) => app.AppUser(
  uid: 'actor',
  name: 'Actor',
  username: 'actor',
  email: '',
  role: role,
  city: 'Riga',
  country: 'Latvia',
  banned: banned,
);

void main() {
  test('only active admins and moderators can initiate transfers', () {
    expect(app.canTransferSpotOwnership(actor(app.UserRole.admin)), isTrue);
    // A moderator without an assigned country cannot transfer a spot.
    expect(
      app.canTransferSpotOwnership(actor(app.UserRole.moderator)),
      isFalse,
    );
    expect(app.canTransferSpotOwnership(actor(app.UserRole.user)), isFalse);
    expect(
      app.canTransferSpotOwnership(actor(app.UserRole.admin, banned: true)),
      isFalse,
    );
  });

  test(
    'transfers from staff and other users move both ownership identities',
    () {
      for (final previous in ['actor', 'another-user']) {
        final fields = app.spotOwnershipTransferFields(
          spot: {
            'addedByUid': previous,
            'ownerUid': 'business-owner',
            'status': 'approved',
            'countryCode': 'RU',
            'name': 'Spot',
          },
          recipientUid: 'recipient',
          recipient: {'username': 'new_owner'},
          actorUid: 'actor',
        );
        expect(fields['addedByUid'], 'recipient');
        expect(fields['ownerUid'], 'recipient');
        expect(fields['addedBy'], 'new_owner');
        expect(fields['ownerUsername'], 'new_owner');
        expect(fields['ownershipTransferredFromUid'], previous);
        expect(fields['previousBusinessOwnerUid'], 'business-owner');
        expect(fields['ownershipTransferredByUid'], 'actor');
        expect(fields.containsKey('status'), isFalse);
        expect(fields.containsKey('countryCode'), isFalse);
        expect(fields.containsKey('name'), isFalse);
      }
    },
  );

  test('deleted, banned and incomplete recipients are rejected', () {
    for (final recipient in <Map<String, dynamic>>[
      {'username': 'recipient', 'deleted': true},
      {'username': 'recipient', 'banned': true},
      {
        'username': 'recipient',
        'banned': true,
        'bannedUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 1)),
        ),
      },
      {'username': ''},
    ]) {
      expect(
        () => app.spotOwnershipTransferFields(
          spot: {'addedByUid': 'old'},
          recipientUid: 'new',
          recipient: recipient,
          actorUid: 'actor',
        ),
        throwsStateError,
      );
    }
  });

  test('ordinary spots with no business owner can be transferred', () {
    final fields = app.spotOwnershipTransferFields(
      spot: {'addedByUid': 'old'},
      recipientUid: 'new',
      recipient: {'username': 'new_owner'},
      actorUid: 'actor',
    );
    expect(fields['ownerUid'], 'new');
    expect(fields['previousBusinessOwnerUid'], '');
  });

  test('a redundant transfer is rejected', () {
    expect(
      () => app.spotOwnershipTransferFields(
        spot: {'addedByUid': 'new', 'ownerUid': 'new'},
        recipientUid: 'new',
        recipient: {'username': 'new_owner'},
        actorUid: 'actor',
      ),
      throwsStateError,
    );
  });
}
