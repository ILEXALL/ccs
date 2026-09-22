import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart'
    show userReportsCollection;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show timestampMillisFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;

Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
regionalUserReportsStream() {
  if (currentUser.role == UserRole.admin) {
    return userReportsCollection()
        .orderBy('createdAtMillis', descending: true)
        .limit(200)
        .debugSnapshots('admin: user reports')
        .map((snapshot) => snapshot.docs);
  }
  final countries = currentUser.moderatorCountryCodes.toList();
  if (currentUser.role != UserRole.moderator || countries.isEmpty) {
    return Stream.value(const []);
  }
  final subscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final pages = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  controller;
  controller = StreamController(
    onListen: () {
      for (var start = 0; start < countries.length; start += 30) {
        final page = start;
        subscriptions.add(
          userReportsCollection()
              .where(
                'countryCode',
                whereIn: countries.sublist(
                  start,
                  math.min(start + 30, countries.length),
                ),
              )
              .debugSnapshots('moderator: regional user reports')
              .listen((snapshot) {
                pages[page] = snapshot.docs;
                if (pages.length == (countries.length / 30).ceil()) {
                  final documents = pages.values.expand((docs) => docs).toList()
                    ..sort(
                      (a, b) =>
                          timestampMillisFromFirebase(
                            b.data()['createdAtMillis'],
                          ).compareTo(
                            timestampMillisFromFirebase(
                              a.data()['createdAtMillis'],
                            ),
                          ),
                    );
                  controller.add(documents);
                }
              }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
