import 'package:ccs_app/features/auth/data/usernames.dart';
import 'package:ccs_app/features/auth/screens/login_screen.dart';
import 'package:ccs_app/features/auth/widgets/apple_sign_in_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppleUserInfo extends Fake implements UserInfo {
  @override
  String get providerId => 'apple.com';
}

class AppleUser extends Fake implements User {
  @override
  bool get isAnonymous => false;
  @override
  List<UserInfo> get providerData => [AppleUserInfo()];
  @override
  String? get displayName => null;
  @override
  String? get email => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channels = <MethodChannel>[];
  final enabledStates = <bool>[];
  int? viewId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    viewId = null;
    enabledStates.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        viewId = args['id'] as int;
        final channel = MethodChannel('ccs/apple_sign_in_button/$viewId');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setEnabled') {
            enabledStates.add(call.arguments as bool);
          }
          return null;
        });
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
  });

  Future<void> nativePress() async {
    await messenger.handlePlatformMessage(
      'ccs/apple_sign_in_button/$viewId',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pressed')),
      (_) {},
    );
  }

  test(
    'returning Apple accounts retain provider and tolerate absent name/email',
    () {
      expect(providerNameForFirebaseUser(AppleUser()), 'apple');
      expect(makeUsernameFromFirebaseUser(AppleUser()), 'ccs_driver');
    },
  );

  testWidgets(
    'native Apple button forwards taps and blocks stale taps while disabled',
    (tester) async {
      var taps = 0;
      Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
          body: AppleSignInButton(onPressed: enabled ? () => taps++ : null),
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(viewId, isNotNull);
      await nativePress();
      expect(taps, 1);
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(enabledStates.last, isFalse);
      await nativePress();
      expect(taps, 1);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(enabledStates.last, isTrue);
      await nativePress();
      expect(taps, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('iOS login remains scrollable on a small landscape screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(AppleSignInButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Sign in with email'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with email').hitTestable(), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'Android retains existing login options without an Apple platform view',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(AppleSignInButton), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Telegram'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
