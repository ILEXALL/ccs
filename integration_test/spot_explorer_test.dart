import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ccs_app/main.dart' as app;

class _OfflineOnly extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network is disabled in the isolated UI pilot');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const seed = int.fromEnvironment('CCS_SEED', defaultValue: 1701);
  const steps = int.fromEnvironment('CCS_STEPS', defaultValue: 40);
  const section = String.fromEnvironment('CCS_SECTION', defaultValue: 'spots');
  final screens = <String, Widget>{
    'spots': const app.AddSpotScreen(),
    'explore': const app.ExploreScreen(),
    'profile': const app.ProfileScreen(),
    'garage': const app.EditGarageScreen(),
    'settings': const app.SettingsScreen(),
    'chats': const app.ChatScreen(),
    'saved': const app.SavedScreen(),
    'submissions': const app.UserSubmissionsScreen(),
    'notifications': const app.NotificationCenterScreen(),
    'friends': const app.FriendsScreen(),
    'xp': const app.XpLeaderboardScreen(),
  };
  testWidgets('Offline screen exploratory pilot', (tester) async {
    final trace = <Map<String, Object?>>[];
    final navigator = GlobalKey<NavigatorState>();
    final random = Random(seed);
    final frameworkErrors = <String>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      frameworkErrors.add(details.toString());
      previousErrorHandler?.call(details);
    };
    HttpOverrides.global = _OfflineOnly();
    app.firebaseReady = false;
    app.currentUser = const app.AppUser(uid: 'synthetic-ui', name: 'UI Test',
      username: 'synthetic_ui', email: 'ui@example.invalid', role: app.UserRole.user,
      city: 'Riga', country: 'Latvia');
    Map<String, dynamic> report(String status, [String? error]) => {
      'status': status, 'seed': seed, 'requestedSteps': steps,
      'scope': '$section offline screen pilot; no login, upload, submission or backend',
      'steps': trace, if (error != null) 'error': error,
      'frameworkErrors': frameworkErrors,
    };
    try {
      if (!screens.containsKey(section)) throw ArgumentError('Unknown section: $section');
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, theme: ThemeData.dark(),
        home: Scaffold(body: Center(child: ElevatedButton(
          onPressed: () => navigator.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => screens[section]!)),
          child: const Text('Open spot form'),
        ))),
      ));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await tester.tap(find.text('Open spot form'));
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < steps; i++) {
        final action = random.nextInt(6);
        final entry = <String, Object?>{'step': i + 1, 'action': action};
        trace.add(entry);
        if (action == 0) {
          final fields = find.byType(TextField).hitTestable();
          if (fields.evaluate().isNotEmpty) {
            final values = ['', 'Synthetic spot', 'x' * 250, 'Riga 123'];
            final value = values[random.nextInt(values.length)];
            entry['action'] = 'enter text in first visible field';
            entry['text'] = value;
            await tester.enterText(fields.first, value);
            final editable = find.descendant(of: fields.first, matching: find.byType(EditableText));
            expect(tester.widget<EditableText>(editable.first).controller.text, value);
            await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          } else {
            entry['action'] = 'no visible text field; skipped';
          }
        } else if (action == 1 || action == 2) {
          final dy = action == 1 ? -300.0 : 300.0;
          entry['action'] = 'scroll form';
          entry['dy'] = dy;
          final scroll = find.byType(Scrollable).hitTestable();
          if (scroll.evaluate().isNotEmpty) {
            await tester.drag(scroll.first, Offset(0, dy));
          } else {
            entry['action'] = 'no visible scroll area; skipped';
          }
        } else if (action == 3) {
          entry['action'] = 'back then reopen form';
          navigator.currentState!.popUntil((route) => route.isFirst);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(find.text('Open spot form'));
        } else {
          final controls = find.byWidgetPredicate((widget) => action == 4
            ? (widget is ButtonStyleButton && widget.onPressed != null) ||
              (widget is IconButton && widget.onPressed != null)
            : (widget is Switch && widget.onChanged != null) ||
              (widget is Checkbox && widget.onChanged != null)).hitTestable();
          final candidates = controls.evaluate().toList();
          if (candidates.isEmpty) {
            entry['action'] = 'no visible enabled control; skipped';
          } else {
            final selected = candidates[random.nextInt(candidates.length)].widget;
            final target = find.byWidget(selected);
            final center = tester.getCenter(target);
            entry['action'] = 'tap control';
            entry['widget'] = selected.toStringShort();
            entry['label'] = find.descendant(of: target, matching: find.byType(Text))
              .evaluate().map((element) => (element.widget as Text).data ?? '').join(' ');
            entry['x'] = center.dx;
            entry['y'] = center.dy;
            await tester.tap(target);
          }
        }
        await tester.pump(const Duration(milliseconds: 500));
        final error = tester.takeException();
        if (error != null) throw error;
        expect(find.byType(Scaffold), findsWidgets);
        binding.reportData = report('running');
        if (i % 10 == 0) {
          await binding.takeScreenshot('step-${i + 1}');
        }
      }
      binding.reportData = report('passed');
      await binding.takeScreenshot('completed');
    } catch (error, stack) {
      binding.reportData = report('failed', '$error\n$stack');
      try {
        await binding.takeScreenshot('failure');
      } catch (captureError) {
        binding.reportData!['screenshotError'] = '$captureError';
      }
      rethrow;
    } finally {
      HttpOverrides.global = null;
      FlutterError.onError = previousErrorHandler;
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
