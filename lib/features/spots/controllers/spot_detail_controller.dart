import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/map/controllers/map_focus.dart'
    show MapFocusRequest, mapFocusRequest;
import 'package:ccs_app/features/spots/models/spot_navigation_result.dart'
    show SpotDetailNavigationResult;
import 'package:ccs_app/features/spots/controllers/spot_detail_view_state.dart';

/// Coordinates actions and data loading for SpotDetailScreen.
class SpotDetailController implements SpotDetailControllerActions {
  final SpotDetailViewState host;
  SpotDetailController(this.host);

  @override
  void groupAccessChanged() {
    if (host.mounted) host.updateView(() {});
  }

  @override
  void showSpotOnMap() {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    if (host.spot.isTemporary && !host.spot.isTemporaryLocationAvailableNow) {
      ScaffoldMessenger.of(viewContext).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            trText('Location not available yet'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    mapFocusRequest.value = MapFocusRequest(
      spotId: host.spot.id,
      coordinates: host.spot.coordinates,
      spot: host.spot,
      routePreview: true,
    );

    // MainScreen listens to mapFocusRequest and switches to the Map tab. The
    // result also lets NotificationCenterScreen close itself so it does not
    // remain on top of the selected Map tab.
    Navigator.of(viewContext).pop(SpotDetailNavigationResult.showMap);
  }

  @override
  Future<void> shareSpotLink() async {
    // Keep the borrowed BuildContext tied to the screen lifecycle.
    late final viewContext = host.context;

    final cleanSpotId = host.spot.id.trim();
    final link = cleanSpotId.isEmpty
        ? 'CCS spot: ${host.spot.name}'
        : 'ccs://spot/$cleanSpotId';
    final publicLink = cleanSpotId.isEmpty
        ? ''
        : 'https://ccs.app/spot/$cleanSpotId';
    final shareText = publicLink.isEmpty
        ? link
        : 'CCS spot: ${host.spot.name}\n$link\n$publicLink';

    await Clipboard.setData(ClipboardData(text: shareText));

    if (!(host.mounted && viewContext.mounted)) {
      return;
    }

    ScaffoldMessenger.of(viewContext).showSnackBar(
      SnackBar(
        backgroundColor: blue,
        content: CcsText(
          trText('Spot link copied.'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
