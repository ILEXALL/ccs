import 'package:ccs_app/features/auth/navigation/sign_out_navigation.dart'
    as sign_out;
import 'navigation/sign_out_navigation.dart';
import 'package:ccs_app/features/auth/navigation/auth_pages.dart' as auth_pages;
import 'app_shell.dart';
import 'gates/splash_screen.dart';
import 'package:ccs_app/features/profile/navigation/profile_navigation.dart'
    as contract0;
import 'package:ccs_app/app/navigation/profile_navigation.dart'
    as implementation0;
import 'package:ccs_app/features/community/chats/navigation/chat_navigation.dart'
    as contract1;
import 'package:ccs_app/app/navigation/chat_navigation.dart' as implementation1;
import 'package:ccs_app/features/notifications/navigation/notification_navigation.dart'
    as contract2;
import 'package:ccs_app/app/navigation/notification_navigation.dart'
    as implementation2;
import 'package:ccs_app/shared/widgets/app_bar_actions.dart' as contract3;
import 'package:ccs_app/app/widgets/app_bar_actions.dart' as implementation3;

/// Wires cross-feature navigation without screen-to-screen dependency cycles.
void configureAppNavigation() {
  auth_pages.signedOutPage = (_) => const SplashScreen();
  auth_pages.signedInPage = (_) => const MainScreen();
  sign_out.showSignedOutScreen = navigateAfterSignOut;
  contract0.profileNavigation = implementation0.navigateToUserProfile;
  contract1.directChatNavigation = implementation1.navigateToDirectChat;
  contract2.notificationNavigation = implementation2.navigateToNotification;
  contract3.appBarActionsBuilder = implementation3.buildAppBarActions;
}
