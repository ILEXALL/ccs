import 'package:flutter/foundation.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/models/spot_status.dart';

class SpotReviewDecision {
  SpotReviewDecision(this.spot, this.status, {this.reason = ''});
  final CarSpot spot;
  final SpotStatus status;
  String reason;
}

/// Keeps drafts across filters and removes only confirmed successful decisions.
class SpotBatchReview extends ChangeNotifier {
  final drafts = <String, SpotReviewDecision>{};
  final errors = <String, String>{};
  bool busy = false;
  bool _closed = false;
  void _emit() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  int completed = 0;
  int total = 0;

  void select(CarSpot spot, SpotStatus status) {
    if (busy) return;
    final previous = drafts[spot.id];
    errors.remove(spot.id);
    if (previous?.status == status) {
      drafts.remove(spot.id);
    } else {
      drafts[spot.id] = SpotReviewDecision(
        spot,
        status,
        reason: previous?.reason ?? '',
      );
    }
    _emit();
  }

  void clear(String id) {
    if (busy) return;
    drafts.remove(id);
    errors.remove(id);
    _emit();
  }

  void reason(String id, String text) {
    if (busy) return;
    drafts[id]?.reason = text;
  }

  Future<int> submit(Future<void> Function(SpotReviewDecision) send) async {
    if (busy || drafts.isEmpty) return 0;
    errors.clear();
    for (final entry in drafts.entries) {
      if (entry.value.status == SpotStatus.rejected &&
          entry.value.reason.trim().isEmpty) {
        errors[entry.key] = 'Write a rejection reason first.';
      }
    }
    if (errors.isNotEmpty) {
      _emit();
      return 0;
    }
    busy = true;
    completed = 0;
    total = drafts.length;
    _emit();
    var succeeded = 0;
    try {
      for (final entry in drafts.entries.toList()) {
        if (_closed) break;
        try {
          await send(entry.value);
          drafts.remove(entry.key);
          succeeded++;
        } catch (error) {
          errors[entry.key] = error is StateError
              ? error.message.toString()
              : 'Could not submit decision. Please try again.';
        }
        completed++;
        _emit();
      }
    } finally {
      busy = false;
      _emit();
    }
    return succeeded;
  }
}
