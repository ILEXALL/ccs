import 'package:ccs_app/features/community/chats/widgets/chat_link_text.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart';
import 'package:ccs_app/core/platform/external_links.dart';
import 'package:ccs_app/core/theme/app_background.dart';
import 'package:ccs_app/features/moderation/screens/spot_review_map_screen.dart';
import 'package:ccs_app/features/moderation/widgets/admin_status_badge.dart';
import 'package:ccs_app/features/spots/models/car_spot.dart';
import 'package:ccs_app/features/spots/models/spot_status.dart';
import 'package:ccs_app/features/spots/widgets/spot_photo.dart';
import 'package:ccs_app/shared/utils/date_formatting.dart';

class BatchSpotReviewCard extends StatelessWidget {
  const BatchSpotReviewCard({
    super.key,
    required this.spot,
    required this.onEdit,
    required this.onDecision,
    required this.onReason,
    required this.onClear,
    this.decision,
    this.reason = '',
    this.error,
  });
  final CarSpot spot;
  final VoidCallback onEdit, onClear;
  final ValueChanged<SpotStatus> onDecision;
  final ValueChanged<String> onReason;
  final SpotStatus? decision;
  final String reason;
  final String? error;

  Widget section(String title, IconData icon, List<Widget> children) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: const Color(0xff90baff)),
                const SizedBox(width: 8),
                Expanded(
                  child: CcsText(
                    title,
                    style: const TextStyle(
                      color: Color(0xff90baff),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget detail(String label, String value) => value.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final labelWidget = CcsText(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              );
              final valueWidget = CcsText(
                value,
                style: const TextStyle(color: Colors.white, height: 1.4),
              );
              if (constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 3),
                    valueWidget,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: constraints.maxWidth * .35,
                    child: labelWidget,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: valueWidget),
                ],
              );
            },
          ),
        );
  String date(int? value) => value == null || value == 0
      ? ''
      : '${formatShortDate(DateTime.fromMillisecondsSinceEpoch(value))} · ${formatClockTime(DateTime.fromMillisecondsSinceEpoch(value))}';

  @override
  Widget build(BuildContext context) {
    final accent = decision == SpotStatus.approved
        ? const Color(0xff64d6a0)
        : decision == SpotStatus.rejected
        ? const Color(0xffff7c87)
        : const Color(0xff549eff);
    final photos = spotPhotoSources(spot);
    return Material(
      color: const Color(0xff111923),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AdminStatusBadge(status: spot.status),
                  const Spacer(),
                  const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 5),
                  const CcsText(
                    'Tap to edit',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              CcsText(
                spot.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const CcsText('Photos, map and details'),
                children: [
                  const SizedBox(height: 6),
                  CcsText(
                    spot.categories.map(trText).join(' · '),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  section('Location', Icons.location_on_outlined, [
                    detail('Location', spot.cityCountry),
                    detail(
                      'Coordinates',
                      '${spot.coordinates.latitude.toStringAsFixed(6)}, ${spot.coordinates.longitude.toStringAsFixed(6)}',
                    ),
                  ]),
                  section('Submission details', Icons.person_outline, [
                    detail('Added by', spot.addedBy),
                    detail('Created', date(spot.createdAtMillis)),
                    if (spot.updatedAtMillis > spot.createdAtMillis)
                      detail('Updated', date(spot.updatedAtMillis)),
                  ]),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 170,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: spotPhotoImage(
                            photos[index],
                            width: 220,
                            height: 170,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (spot.description.isNotEmpty)
                    section('Description', Icons.notes_outlined, [
                      ChatLinkText(
                        spot.description,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.45,
                        ),
                      ),
                    ]),
                  section('Visibility', Icons.visibility_outlined, [
                    detail(
                      'Visibility',
                      trText(spot.isGroupSpot ? 'Private event' : 'Public'),
                    ),
                    if (spot.sharedGroups.isNotEmpty)
                      detail(
                        'Groups',
                        spot.sharedGroups
                            .map((g) => g['name'] ?? g['id'] ?? '')
                            .join(', '),
                      ),
                    if (spot.verifiedOnly)
                      detail('Access', trText('Verified users only')),
                  ]),
                  if (spot.isTemporary)
                    section('Event schedule', Icons.event_outlined, [
                      detail('Starts', date(spot.startsAtMillis)),
                      detail('Ends', date(spot.expiresAtMillis)),
                      detail('Location reveal', date(spot.showOnMapAtMillis)),
                    ]),
                  if ([
                    spot.contactPhone,
                    spot.contactInstagram,
                    spot.contactEmail,
                    spot.ownerUsername,
                  ].any((value) => value.trim().isNotEmpty))
                    section('Contact details', Icons.contact_phone_outlined, [
                      detail('Phone', spot.contactPhone),
                      detail('Instagram', spot.contactInstagram),
                      detail('Email', spot.contactEmail),
                      detail('Owner', spot.ownerUsername),
                    ]),
                  if (!spot.isTemporary && spot.hasOpeningHours)
                    section('Opening hours', Icons.schedule, [
                      for (final day
                          in (spot.openingHours.keys.toList()..sort()))
                        detail(
                          [
                            'Monday',
                            'Tuesday',
                            'Wednesday',
                            'Thursday',
                            'Friday',
                            'Saturday',
                            'Sunday',
                          ][day - 1],
                          spot.openingHours[day]!.isOpen
                              ? '${spot.openingHours[day]!.opensAt} – ${spot.openingHours[day]!.closesAt}'
                              : trText('Closed'),
                        ),
                    ]),
                  section('Spot details', Icons.info_outline, [
                    detail('Best time', trText(spot.bestTime)),
                    detail('Parking', trText(spot.parking)),
                    detail('Road quality', trText(spot.roadQuality)),
                    detail(
                      'Low car friendly',
                      trText(spot.lowCarFriendly ? 'Yes' : 'No'),
                    ),
                    detail('Police risk', trText(spot.policeRisk)),
                    detail('Traffic', trText(spot.traffic)),
                    detail('Lighting', trText(spot.lighting)),
                    detail('Crowd', trText(spot.crowd)),
                  ]),
                  if (spot.rejectionReason.trim().isNotEmpty)
                    section('Rejection reason', Icons.feedback_outlined, [
                      CcsText(spot.rejectionReason),
                    ]),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          appPageRoute(
                            builder: (_) =>
                                AdminSpotLocationReviewMapScreen(spot: spot),
                          ),
                        ),
                        icon: const Icon(Icons.map_outlined),
                        label: const CcsText('Map'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => launchExternalUrl(
                          context,
                          'https://www.google.com/maps/search/?api=1&query=${spot.coordinates.latitude},${spot.coordinates.longitude}',
                        ),
                        icon: const Icon(Icons.open_in_new),
                        label: const CcsText('Google Maps'),
                      ),
                      if (spot.reelLink.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () =>
                              launchExternalUrl(context, spot.reelLink),
                          icon: const Icon(Icons.play_circle_outline),
                          label: const CcsText('Video'),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 8, color: Colors.white12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const CcsText('Approve'),
                      avatar: const Icon(Icons.check, size: 18),
                      selected: decision == SpotStatus.approved,
                      selectedColor: const Color(0xff225840),
                      onSelected: (_) => onDecision(SpotStatus.approved),
                    ),
                  ),
                  Expanded(
                    child: ChoiceChip(
                      label: const CcsText('Reject'),
                      avatar: const Icon(Icons.close, size: 18),
                      selected: decision == SpotStatus.rejected,
                      selectedColor: const Color(0xff652e38),
                      onSelected: (_) => onDecision(SpotStatus.rejected),
                    ),
                  ),
                  if (decision != null)
                    IconButton(
                      tooltip: trText('Clear decision'),
                      onPressed: onClear,
                      icon: const Icon(Icons.undo),
                    ),
                ],
              ),
              if (decision == SpotStatus.rejected) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('reason-${spot.id}'),
                  initialValue: reason,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 300,
                  onChanged: onReason,
                  decoration: InputDecoration(
                    labelText: trText('Rejection reason'),
                    hintText: trText('Write the reason the user will see...'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: CcsText(
                    trText(error!),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
