/// Account lifecycle actions are installed by app composition. Spot syncing
/// requests them without importing the session coordinator that starts it.
late void Function() restartSpotAccountWatcher;
late Future<void> Function() stopSpotAccountServices;
