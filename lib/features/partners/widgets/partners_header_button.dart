import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/partners/data/partners_repository.dart'
    show
        ccsPartnersCollection,
        currentUserCanManagePartners,
        sortedVisiblePartners;
import 'package:ccs_app/features/partners/models/partner.dart' show CcsPartner;
import 'package:ccs_app/features/partners/screens/partners_screen.dart'
    show PartnersScreen;

class PartnersHeaderButton extends StatefulWidget {
  const PartnersHeaderButton({super.key});

  @override
  State<PartnersHeaderButton> createState() => _PartnersHeaderButtonState();
}

class _PartnersHeaderButtonState extends State<PartnersHeaderButton> {
  static const int _initialLoopPage = 10000;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> partnerStream;
  late final PageController pageController;
  Timer? rotationTimer;
  int partnerCount = 0;
  int currentLoopPage = _initialLoopPage;

  @override
  void initState() {
    super.initState();
    pageController = PageController(initialPage: _initialLoopPage);
    partnerStream = ccsPartnersCollection().debugSnapshots(
      'partners: header listener',
    );
    rotationTimer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (!mounted || partnerCount <= 1 || !pageController.hasClients) return;
      currentLoopPage += 1;
      try {
        pageController.animateToPage(
          currentLoopPage,
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeInOutCubicEmphasized,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    rotationTimer?.cancel();
    pageController.dispose();
    super.dispose();
  }

  void openPartners() {
    Navigator.push(
      context,
      appPageRoute(builder: (_) => const PartnersScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: partnerStream,
      builder: (context, snapshot) {
        final partners = snapshot.hasData
            ? sortedVisiblePartners(snapshot.data!)
            : const <CcsPartner>[];
        partnerCount = partners.length;
        final hasActivePartner =
            snapshot.data?.docs.any(
              (doc) => CcsPartner.fromFirestore(doc).active,
            ) ??
            false;
        if (!currentUserCanManagePartners && !hasActivePartner) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: openPartners,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 50,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(3, 3, 5, 3),
              decoration: BoxDecoration(
                color: const Color(0xFF061121).withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: blue.withValues(alpha: 0.62),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: blue.withValues(alpha: 0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Builder(
                builder: (context) {
                  if (partnerCount == 0) {
                    return const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.handshake_outlined, color: blue, size: 16),
                        SizedBox(width: 6),
                        Flexible(
                          child: CcsText(
                            'Partners',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: PageView.builder(
                              controller: pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              onPageChanged: (page) => currentLoopPage = page,
                              itemBuilder: (context, page) {
                                final partner = partners[page % partnerCount];
                                return Image.network(
                                  partner.logoUrl,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(
                                      Icons.handshake_outlined,
                                      color: blue,
                                      size: 23,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const SizedBox(
                        width: 43,
                        child: CcsText(
                          'Official\nPartner',
                          maxLines: 2,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: blue,
                            fontSize: 9.2,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
