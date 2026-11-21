import 'package:flutter/material.dart';
import 'package:ccs_app/features/community/chats/widgets/chat_link_text.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'spot_detail_header.dart';
import 'spot_detail_actions.dart';
import 'spot_info_tag.dart';

/// Keep the destination, its actions, and its context together as one surface.
class SpotDetailOverview extends StatelessWidget {
  const SpotDetailOverview({
    super.key,
    required this.spot,
    required this.onShowMap,
  });

  final CarSpot spot;
  final VoidCallback onShowMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF28313E), Color(0xFF1D242E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3A4555)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpotDetailCompactHeader(spot: spot),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final category in spot.categories)
                SpotInfoTag(label: category, icon: Icons.local_offer_outlined),
              SpotDetailEngagementPanel(spot: spot),
            ],
          ),
          const SizedBox(height: 12),
          SpotRouteActions(spot: spot, onShowMap: onShowMap),
          if (spot.description.trim().isNotEmpty) ...[
            const Divider(height: 32, color: Color(0xFF3A4555)),
            ChatLinkText(
              spot.description,
              softWrap: true,
              style: const TextStyle(
                color: Color(0xFFDFE5EE),
                fontSize: 15,
                height: 1.55,
              ),
            ),
          ],
          const Divider(height: 32, color: Color(0xFF3A4555)),
          SpotDetailMetaRow(spot: spot),
        ],
      ),
    );
  }
}
