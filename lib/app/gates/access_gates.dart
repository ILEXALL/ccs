import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/app/gates/maintenance_state.dart'
    show
        MaintenanceModeConfig,
        appVersionIsOutdated,
        currentAppVersion,
        maintenanceModeConfig,
        refreshMaintenanceMode;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart'
    show currentUser, maintenanceAccessRevision;
import 'package:ccs_app/features/auth/data/session_lifecycle.dart'
    show signOutCurrentAccount;
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart'
    show DeleteAccountTile;
import 'package:ccs_app/shared/models/user_role.dart' show UserRole;
import 'package:ccs_app/shared/utils/date_formatting.dart'
    show formatShortDateTime;
import 'package:ccs_app/shared/widgets/app_logo.dart' show CcsWordmark;

class MaintenanceModeGate extends StatelessWidget {
  final Widget child;

  const MaintenanceModeGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        maintenanceModeConfig,
        maintenanceAccessRevision,
      ]),
      builder: (context, _) {
        final config = maintenanceModeConfig.value;
        if (appVersionIsOutdated(config)) {
          return OutdatedAppScreen(config: config);
        }

        final isSignedIn = FirebaseAuth.instance.currentUser != null;
        final canAdminBypass =
            isSignedIn &&
            config.allowAdminBypass &&
            currentUser.role == UserRole.admin;

        // Keep login reachable so an administrator can authenticate during maintenance.
        if (!config.maintenanceEnabled || !isSignedIn || canAdminBypass) {
          return child;
        }

        return MaintenanceModeScreen(config: config);
      },
    );
  }
}

class BannedUserGate extends StatelessWidget {
  final Widget child;

  const BannedUserGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: maintenanceAccessRevision,
      builder: (context, _) {
        final isSignedIn = FirebaseAuth.instance.currentUser != null;
        if (!isSignedIn || !currentUser.banActive) {
          return child;
        }

        return const BannedUserScreen();
      },
    );
  }
}

class BannedUserScreen extends StatefulWidget {
  const BannedUserScreen({super.key});

  @override
  State<BannedUserScreen> createState() => _BannedUserScreenState();
}

class _BannedUserScreenState extends State<BannedUserScreen>
    with LanguageReactiveState {
  bool signingOut = false;

  String get untilLabel {
    final bannedUntilMillis = currentUser.bannedUntilMillis;
    if (bannedUntilMillis == null) {
      return trText('Permanent ban');
    }

    return formatShortDateTime(
      DateTime.fromMillisecondsSinceEpoch(bannedUntilMillis),
    );
  }

  Future<void> signOut() async {
    if (signingOut) {
      return;
    }

    setState(() => signingOut = true);
    try {
      await signOutCurrentAccount();
    } finally {
      if (mounted) {
        setState(() => signingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cleanReason = currentUser.banReason.trim();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.78)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.redAccent),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CcsWordmark(width: 148),
                      const SizedBox(height: 22),
                      const Icon(
                        Icons.block,
                        color: Colors.redAccent,
                        size: 44,
                      ),
                      const SizedBox(height: 14),
                      CcsText(
                        trText('You are banned'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CcsText(
                        trText('Your account is blocked from using CCS.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _VersionInfoRow(
                        label: trText('Banned until'),
                        value: untilLabel,
                      ),
                      const SizedBox(height: 10),
                      _BanInfoBox(
                        title: trText('Reason'),
                        text: cleanReason.isEmpty
                            ? trText('No reason provided.')
                            : cleanReason,
                      ),
                      const SizedBox(height: 18),
                      CcsText(
                        trText('Contact an administrator if this looks wrong.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: signingOut ? null : signOut,
                        icon: const Icon(Icons.logout, color: Colors.white),
                        label: CcsText(
                          signingOut
                              ? trText('Signing out...')
                              : trText('Sign out'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          disabledBackgroundColor: Colors.white24,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const DeleteAccountTile(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BanInfoBox extends StatelessWidget {
  final String title;
  final String text;

  const _BanInfoBox({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CcsText(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          CcsText(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class OutdatedAppScreen extends StatelessWidget {
  final MaintenanceModeConfig config;

  const OutdatedAppScreen({super.key, required this.config});

  String normalizedUpdateContact(String contact) {
    var cleanContact = contact.trim();
    while (cleanContact.length >= 2 &&
        ((cleanContact.startsWith('"') && cleanContact.endsWith('"')) ||
            (cleanContact.startsWith("'") && cleanContact.endsWith("'")))) {
      cleanContact = cleanContact.substring(1, cleanContact.length - 1).trim();
    }

    return cleanContact;
  }

  Uri? updateContactUri(String contact) {
    var cleanContact = normalizedUpdateContact(contact);
    if (cleanContact.isEmpty) {
      return null;
    }

    final lowerContact = cleanContact.toLowerCase();
    if (cleanContact.startsWith('@') &&
        (lowerContact.startsWith('@http://') ||
            lowerContact.startsWith('@https://') ||
            lowerContact.startsWith('@t.me/') ||
            lowerContact.startsWith('@telegram.me/'))) {
      cleanContact = cleanContact.substring(1);
    }

    final lowerCleanContact = cleanContact.toLowerCase();
    if (lowerCleanContact.startsWith('http://') ||
        lowerCleanContact.startsWith('https://')) {
      return Uri.tryParse(cleanContact);
    }

    if (lowerCleanContact.startsWith('t.me/') ||
        lowerCleanContact.startsWith('telegram.me/')) {
      return Uri.tryParse('https://$cleanContact');
    }

    if (cleanContact.startsWith('@')) {
      final username = cleanContact.substring(1).trim();
      if (username.isEmpty) {
        return null;
      }

      return Uri.https('t.me', '/$username');
    }

    return null;
  }

  Future<void> openUpdateContact(BuildContext context, String contact) async {
    final uri = updateContactUri(contact);

    if (uri == null) {
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            trText('Could not open update contact.'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = config.updateContact.trim().isEmpty
        ? '@ccs'
        : normalizedUpdateContact(config.updateContact);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.62)),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: panelGlass,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CcsWordmark(width: 148),
                      const SizedBox(height: 22),
                      Icon(
                        Icons.system_update_alt,
                        color: Colors.redAccent.shade100,
                        size: 42,
                      ),
                      const SizedBox(height: 14),
                      CcsText(
                        trText('Update required'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CcsText(
                        trText(
                          'This version of CCS is outdated. Please update the app before entering.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _VersionInfoRow(
                        label: trText('Your version'),
                        value: currentAppVersion.trim().isEmpty
                            ? '-'
                            : currentAppVersion.trim(),
                      ),
                      const SizedBox(height: 10),
                      _VersionInfoRow(
                        label: trText('Required version'),
                        value: config.minimumAppVersion.trim(),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            CcsText(
                              trText('Contact for update'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => unawaited(
                                openUpdateContact(context, contact),
                              ),
                              icon: const Icon(Icons.send, color: Colors.white),
                              label: const CcsText(
                                'Telegram',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blue,
                                minimumSize: const Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _VersionInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: CcsText(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CcsText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class MaintenanceModeScreen extends StatelessWidget {
  final MaintenanceModeConfig config;

  const MaintenanceModeScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.png', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.82)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CcsWordmark(width: 196),
                  const SizedBox(height: 38),
                  const Icon(
                    Icons.build_circle_outlined,
                    size: 54,
                    color: blue,
                  ),
                  const SizedBox(height: 22),
                  material.Text(
                    config.maintenanceTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: material.Text(
                      config.maintenanceMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: () => unawaited(refreshMaintenanceMode()),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const CcsText(
                      'Retry',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 15,
                      ),
                      elevation: 10,
                      shadowColor: blue.withValues(alpha: 0.36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
