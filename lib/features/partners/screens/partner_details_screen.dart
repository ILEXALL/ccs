import 'package:ccs_app/shared/media/photo_gallery.dart' show SpotPhotoCarousel;
import 'dart:async';
import 'package:ccs_app/features/partners/widgets/partner_view_counter.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/platform/external_links.dart'
    show launchExternalUrl;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/partners/data/partners_repository.dart'
    show currentUserCanManagePartners;
import 'package:ccs_app/features/partners/models/partner.dart' show CcsPartner;
import 'package:ccs_app/features/partners/screens/add_partner_screen.dart'
    show AddPartnerScreen;

class PartnerDetailsScreen extends StatelessWidget {
  final CcsPartner partner;

  const PartnerDetailsScreen({super.key, required this.partner});

  Widget contactButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: CcsText(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: blue,
        side: BorderSide(color: blue.withValues(alpha: 0.45)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = <Widget>[
      if (partner.phone.isNotEmpty)
        contactButton(
          context,
          icon: Icons.phone_outlined,
          label: 'Phone',
          onTap: () => unawaited(
            launchUrl(
              Uri(scheme: 'tel', path: partner.phone),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      if (partner.website.isNotEmpty)
        contactButton(
          context,
          icon: Icons.language,
          label: 'Website',
          onTap: () => unawaited(launchExternalUrl(context, partner.website)),
        ),
      if (partner.instagram.isNotEmpty)
        contactButton(
          context,
          icon: Icons.camera_alt_outlined,
          label: 'Instagram',
          onTap: () => unawaited(
            launchExternalUrl(context, partner.instagram, kind: 'instagram'),
          ),
        ),
      if (partner.telegram.isNotEmpty)
        contactButton(
          context,
          icon: Icons.send_outlined,
          label: 'Telegram',
          onTap: () => unawaited(
            launchExternalUrl(context, partner.telegram, kind: 'telegram'),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(partner.name),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          if (currentUserCanManagePartners)
            IconButton(
              tooltip: 'Edit partner',
              onPressed: () {
                Navigator.push(
                  context,
                  appPageRoute(
                    builder: (_) => AddPartnerScreen(partner: partner),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          children: [
            Container(
              height: 150,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: panelGlass,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: blue.withValues(alpha: 0.28)),
              ),
              child: Image.network(
                partner.logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.handshake_outlined, color: blue, size: 52),
              ),
            ),
            const SizedBox(height: 14),
            CcsText(
              partner.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            PartnerViewCounter(partnerId: partner.id),
            const CcsText(
              'Official CCS Partner',
              style: TextStyle(
                color: blue,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (partner.bio.isNotEmpty) ...[
              const SizedBox(height: 18),
              const CcsText(
                'About',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              CcsText(
                partner.bio,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (contacts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: contacts),
            ],
            if (partner.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 22),
              const CcsText(
                'Gallery',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              SpotPhotoCarousel.photos(sources: partner.photoUrls, height: 260),
            ],
          ],
        ),
      ),
    );
  }
}
