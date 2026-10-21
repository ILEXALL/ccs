import 'package:ccs_app/features/moderation/data/spot_review_filters.dart'
    show adminReviewCountryCodes;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ccs_app/core/firestore/collections.dart';
import 'package:ccs_app/features/moderation/controllers/spot_batch_review.dart';
import 'package:ccs_app/features/moderation/data/spot_review_lease.dart';
import 'package:ccs_app/features/spots/data/spot_mutations.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';

Future<void> submitSpotReviewDecision(
  SpotReviewDecision decision, {
  required String countrySessionId,
}) async {
  if (!adminReviewCountryCodes().contains(decision.spot.effectiveCountryCode)) {
    throw StateError('This country is no longer available for review.');
  }
  final lease = SpotReviewLease(
    decision.spot.id,
    countrySessionId: countrySessionId,
  );
  try {
    if (!await lease.acquire()) {
      throw StateError('Another reviewer has this spot open.');
    }
    final doc = await spotsCollection()
        .doc(decision.spot.id)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    if (!doc.exists) throw StateError('Spot is no longer available');
    final fresh = CarSpot.fromFirestore(doc);
    if (fresh.status != decision.spot.status ||
        fresh.updatedAtMillis != decision.spot.updatedAtMillis) {
      throw StateError(
        'Spot changed. Clear the selection and review it again.',
      );
    }
    await lease.ensureActive();
    await updateSpotStatus(
      fresh,
      decision.status,
      reviewSessionId: lease.sessionId,
      rejectionReason: decision.reason.trim(),
    );
  } finally {
    lease.dispose();
  }
}
