import 'package:ccs_app/features/auth/data/session_lifecycle.dart';
import 'package:ccs_app/features/spots/data/spot_account_hooks.dart';

/// Binds account-scoped services once, before bootstrap starts subscriptions.
void configureAppServices() {
  restartSpotAccountWatcher = startCurrentUserDocumentWatcher;
  stopSpotAccountServices = stopCurrentUserAppServicesForAccessBlock;
}
