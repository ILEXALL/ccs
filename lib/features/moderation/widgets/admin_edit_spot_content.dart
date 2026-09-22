import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/widgets/spot_photo.dart'
    show SpotPhotoPlaceholder;
import 'package:ccs_app/features/moderation/controllers/admin_edit_spot_view_state.dart';

/// Renders reusable sections for AdminEditSpotScreen.
class AdminEditSpotContent implements AdminEditSpotContentActions {
  final AdminEditSpotViewState host;
  AdminEditSpotContent(this.host);

  @override
  Widget photoThumb({
    required int index,
    required String label,
    required String source,
    required VoidCallback onRemove,
    required bool isLocal,
  }) {
    final image = isLocal
        ? Image.file(
            File(source),
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                SpotPhotoPlaceholder(width: 88, height: 88),
          )
        : Image.network(
            source,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                SpotPhotoPlaceholder(width: 88, height: 88),
          );

    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: index == 0
                  ? blue.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: CcsText(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}
