import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase, stringListFromFirebase;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugDocumentReferenceExtension;
import 'package:ccs_app/features/auth/data/auth_state.dart' show firebaseReady;

class MaintenanceModeConfig {
  final bool maintenanceEnabled;
  final String maintenanceTitle;
  final String maintenanceMessage;
  final bool allowAdminBypass;
  final String minimumAppVersion;
  final String updateContact;
  final Set<String> bannedCountryCodes;

  const MaintenanceModeConfig({
    required this.maintenanceEnabled,
    required this.maintenanceTitle,
    required this.maintenanceMessage,
    required this.allowAdminBypass,
    required this.minimumAppVersion,
    required this.updateContact,
    required this.bannedCountryCodes,
  });

  static const disabled = MaintenanceModeConfig(
    maintenanceEnabled: false,
    maintenanceTitle: 'Maintenance',
    maintenanceMessage: 'CCS will be back shortly.',
    allowAdminBypass: false,
    minimumAppVersion: '',
    updateContact: '@ccs',
    bannedCountryCodes: <String>{},
  );

  factory MaintenanceModeConfig.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      return disabled;
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    return MaintenanceModeConfig(
      maintenanceEnabled: data['maintenanceEnabled'] == true,
      maintenanceTitle: stringFromFirebase(
        data['maintenanceTitle'],
        'Maintenance',
      ),
      maintenanceMessage: stringFromFirebase(
        data['maintenanceMessage'],
        'CCS will be back shortly.',
      ),
      allowAdminBypass: data['allowAdminBypass'] == true,
      minimumAppVersion: stringFromFirebase(data['minimumAppVersion'], ''),
      updateContact: stringFromFirebase(data['updateContact'], '@ccs'),
      bannedCountryCodes:
          stringListFromFirebase(data['bannedCountryCodes'], const <String>[])
              .map((code) => code.trim().toUpperCase())
              .where((code) => code.isNotEmpty)
              .toSet(),
    );
  }
}

String currentAppVersion = '';

final maintenanceModeConfig = ValueNotifier<MaintenanceModeConfig>(
  MaintenanceModeConfig.disabled,
);

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
maintenanceModeSubscription;

DocumentReference<Map<String, dynamic>> maintenanceModeDocument() {
  return FirebaseFirestore.instance.collection('app_config').doc('main');
}

int compareAppVersions(String currentVersion, String requiredVersion) {
  final currentParts = currentVersion
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  final requiredParts = requiredVersion
      .split('+')
      .first
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  final maxLength = math.max(currentParts.length, requiredParts.length);

  for (var index = 0; index < maxLength; index++) {
    final currentPart = index < currentParts.length ? currentParts[index] : 0;
    final requiredPart = index < requiredParts.length
        ? requiredParts[index]
        : 0;

    if (currentPart != requiredPart) {
      return currentPart.compareTo(requiredPart);
    }
  }

  return 0;
}

bool appVersionIsOutdated(MaintenanceModeConfig config) {
  final requiredVersion = config.minimumAppVersion.trim();
  final localVersion = currentAppVersion.trim();

  if (requiredVersion.isEmpty || localVersion.isEmpty) {
    return false;
  }

  return compareAppVersions(localVersion, requiredVersion) < 0;
}

Future<void> refreshMaintenanceMode() async {
  if (!firebaseReady) {
    return;
  }

  try {
    final snapshot = await maintenanceModeDocument().debugGet(
      null,
      'startup: maintenance mode one-shot get',
    );
    maintenanceModeConfig.value = MaintenanceModeConfig.fromSnapshot(snapshot);
  } catch (error) {
    debugPrint('Maintenance config refresh failed: $error');
  }
}

Future<void> initializeMaintenanceMode() async {
  await maintenanceModeSubscription?.cancel();
  await refreshMaintenanceMode();

  maintenanceModeSubscription = maintenanceModeDocument()
      .debugSnapshots('startup: maintenance mode listener')
      .listen(
        (snapshot) {
          maintenanceModeConfig.value = MaintenanceModeConfig.fromSnapshot(
            snapshot,
          );
        },
        onError: (Object error) {
          debugPrint('Maintenance config watcher failed: $error');
        },
      );
}
