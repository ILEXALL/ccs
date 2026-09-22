import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/partners/data/partners_repository.dart'
    show ccsPartnersCollection, currentUserCanManagePartners, sortedPartners;
import 'package:ccs_app/features/partners/models/partner.dart' show CcsPartner;
import 'package:ccs_app/features/partners/screens/add_partner_screen.dart'
    show AddPartnerScreen;
import 'package:ccs_app/features/partners/screens/partner_details_screen.dart'
    show PartnerDetailsScreen;
import 'package:ccs_app/shared/widgets/empty_state_card.dart'
    show EmptyStateCard;

class PartnersScreen extends StatefulWidget {
  const PartnersScreen({super.key});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> partnerStream;

  @override
  void initState() {
    super.initState();
    partnerStream = ccsPartnersCollection().debugSnapshots(
      'partners: full list listener',
    );
  }

  void addPartner() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const AddPartnerScreen()),
    );
  }

  void editPartner(CcsPartner partner) {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => AddPartnerScreen(partner: partner)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const CcsText('CCS Partners'),
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        actions: [
          if (currentUserCanManagePartners)
            IconButton(
              tooltip: 'Add partner',
              onPressed: addPartner,
              icon: const Icon(Icons.add_business_outlined),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: partnerStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: blue));
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CcsText(
                  'Could not load partners.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          final partners = snapshot.hasData
              ? sortedPartners(
                  snapshot.data!,
                  includeInactive: currentUserCanManagePartners,
                )
              : const <CcsPartner>[];
          if (partners.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              children: [
                const EmptyStateCard(
                  icon: Icons.handshake_outlined,
                  title: 'No partners yet',
                  text: 'Official CCS partners will appear here.',
                ),
                if (currentUserCanManagePartners) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: addPartner,
                    icon: const Icon(Icons.add),
                    label: const CcsText('Add first partner'),
                  ),
                ],
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            itemCount: partners.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final partner = partners[index];
              return _PartnerListCard(
                partner: partner,
                onTap: () => Navigator.push(
                  context,
                  appPageRoute(
                    builder: (_) => PartnerDetailsScreen(partner: partner),
                  ),
                ),
                onEdit: currentUserCanManagePartners
                    ? () => editPartner(partner)
                    : null,
              );
            },
          );
        },
      ),
      floatingActionButton: currentUserCanManagePartners
          ? FloatingActionButton.extended(
              onPressed: addPartner,
              backgroundColor: blue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_outlined),
              label: const CcsText('Add partner'),
            )
          : null,
    );
  }
}

class _PartnerListCard extends StatelessWidget {
  final CcsPartner partner;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _PartnerListCard({
    required this.partner,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panelGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: blue.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 58,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Image.network(
                  partner.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.handshake_outlined, color: blue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CcsText(
                      partner.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CcsText(
                      partner.active
                          ? 'Official CCS Partner'
                          : 'Inactive partner',
                      style: TextStyle(
                        color: partner.active ? blue : Colors.orangeAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit partner',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, color: blue, size: 20),
                )
              else
                const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
