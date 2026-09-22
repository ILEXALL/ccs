import 'dart:async';
import 'package:ccs_app/app/app_navigation.dart';
import 'package:ccs_app/app/app_services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  configureAppNavigation();
  configureAppServices();
  await testMain();
}
