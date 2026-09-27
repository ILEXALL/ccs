import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart' show telegramAuthBaseUrl;
import 'package:ccs_app/core/network/json_http.dart';
import 'package:ccs_app/features/community/forum/data/forum_topics.dart'
    show temporarySpotForumDescription;
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/data/spot_serialization.dart';

Map<String, Object?> groupSpotCreationBody(CarSpot spot) {
  final data = spotToFirestoreData(spot)
    ..remove('coordinates')
    ..remove('updatedAt');
  for (final key in ['startsAt', 'expiresAt', 'showOnMapAt']) {
    final value = data[key];
    if (value is Timestamp) data[key] = value.millisecondsSinceEpoch;
  }
  return {
    'spotId': spot.id,
    'spot': data,
    'topicDescription': temporarySpotForumDescription(spot),
  };
}

Future<void> createGroupSpotOnServer(CarSpot spot) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.uid != spot.addedByUid) {
    throw StateError('Sign in again before creating this spot.');
  }
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) throw StateError('Sign in again.');
  final result = await postJsonToUrl(
    '$telegramAuthBaseUrl/api/group-spot-create',
    groupSpotCreationBody(spot),
    headers: {'Authorization': 'Bearer $token'},
    logResponse: false,
  );
  if (result['spotId'] != spot.id) {
    throw StateError('The server did not confirm spot creation.');
  }
}
