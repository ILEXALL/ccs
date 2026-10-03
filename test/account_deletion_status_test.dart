import 'dart:async';
import 'package:ccs_app/features/auth/widgets/account_deletion_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('refresh shows feedback while processing and then completion', (
    tester,
  ) async {
    var response = Completer<String?>()..complete('processing');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountDeletionStatus(loadStatus: () => response.future),
        ),
      ),
    );
    await tester.pumpAndSettle();
    response = Completer<String?>();
    await tester.tap(find.text('Check deletion status'));
    await tester.pump();
    // Returning the assigned Future from setState throws in debug builds and
    // prevents FutureBuilder from subscribing to the refreshed status.
    expect(tester.takeException(), isNull);
    expect(find.text('Checking…'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    response.complete('processing');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Status checked: deletion is still processing.'),
      findsOneWidget,
    );
    response = Completer<String?>()..complete('complete');
    await tester.tap(find.text('Check deletion status'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your account and associated data have been deleted.'),
      findsOneWidget,
    );
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('failed refresh remains retryable', (tester) async {
    var fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountDeletionStatus(
            loadStatus: () async {
              if (fail) throw StateError('offline');
              return 'processing';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    fail = true;
    await tester.tap(find.text('Check deletion status'));
    await tester.pumpAndSettle();
    expect(find.text('Could not check deletion status.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Check deletion status'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Status checked: deletion is still processing.'),
      findsOneWidget,
    );
  });
}
