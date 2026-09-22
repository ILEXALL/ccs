import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panel;
import 'package:ccs_app/features/spots/data/saved_spots.dart'
    show saveSavedSpotIds;
import 'package:ccs_app/features/spots/models/car_spot.dart' show isSameSpot;
import 'package:ccs_app/features/spots/data/spot_state.dart' show savedSpots;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

class SaveSpotButton extends StatelessWidget {
  final CarSpot spot;
  final bool compact;

  const SaveSpotButton({super.key, required this.spot, this.compact = false});

  bool isSaved(List<CarSpot> spots) {
    return spots.any((savedSpot) => isSameSpot(savedSpot, spot));
  }

  void toggleSaved(BuildContext context, bool saved) {
    if (saved) {
      savedSpots.value = savedSpots.value
          .where((savedSpot) => !isSameSpot(savedSpot, spot))
          .toList();
    } else {
      savedSpots.value = [spot, ...savedSpots.value];
    }
    unawaited(saveSavedSpotIds());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: saved ? panel : blue,
        content: CcsText(
          saved ? 'Spot removed from saved.' : 'Spot saved.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CarSpot>>(
      valueListenable: savedSpots,
      builder: (context, spots, _) {
        final saved = isSaved(spots);

        if (compact) {
          return SizedBox(
            width: 40,
            height: 30,
            child: OutlinedButton(
              onPressed: () => toggleSaved(context, saved),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: saved
                    ? blue.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.06),
                foregroundColor: saved ? blue : Colors.white70,
                side: BorderSide(
                  color: saved ? blue : Colors.white24,
                  width: saved ? 1.4 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                size: 16,
              ),
            ),
          );
        }

        return SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => toggleSaved(context, saved),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            label: CcsText(saved ? 'Saved Spot' : 'Save Spot'),
            style: OutlinedButton.styleFrom(
              foregroundColor: saved ? blue : Colors.white,
              side: BorderSide(color: saved ? blue : Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }
}
