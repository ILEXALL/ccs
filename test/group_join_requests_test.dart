import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  for (final decision in ['accepted', 'rejected']) {
    testWidgets(
      '$decision succeeds and refresh never returns a Future from setState',
      (tester) async {
        var pending = true;
        var loads = 0;
        final decisions = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: app.GroupJoinRequestsScreen(
              chatId: 'group',
              applicantLoader: (_) async => null,
              requestAction: (body) async {
                if (body['action'] == 'decide') {
                  decisions.add(body['decision'] as String);
                  pending = false;
                  return {'status': decision};
                }
                loads++;
                return {
                  'requests': [
                    if (pending) {'uid': 'applicant', 'username': 'driver'},
                  ],
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('View profile'), findsOneWidget);
        await tester.tap(find.byTooltip('Refresh'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.text(decision == 'accepted' ? 'Accept' : 'Reject'),
        );
        await tester.pumpAndSettle();
        expect(decisions, [decision]);
        expect(loads, 3);
        expect(find.text('No pending requests.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  }

  testWidgets('failed decision preserves the applicant for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: app.GroupJoinRequestsScreen(
          chatId: 'group',
          applicantLoader: (_) async => null,
          requestAction: (body) async {
            if (body['action'] == 'decide')
              throw Exception('Network unavailable');
            return {
              'requests': [
                {'uid': 'applicant', 'username': 'driver'},
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(
      find.text('Could not submit decision. Please retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
