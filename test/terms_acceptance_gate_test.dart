import 'dart:async';
import 'package:ccs_app/app/gates/terms_acceptance_gate.dart';
import 'package:ccs_app/features/auth/widgets/legal_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({
    required Future<bool> Function() load,
    required Future<void> Function() save,
  }) => MaterialApp(
    theme: ThemeData.dark(),
    home: TermsAcceptanceGate(
      loadAcceptance: load,
      saveAcceptance: save,
      signOut: () async {},
      child: const Scaffold(body: Text('Community content')),
    ),
  );

  testWidgets('saved acceptance check never flashes the consent form', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(app(load: () => pending.future, save: () async {}));
    expect(find.text('Community rules and your content'), findsNothing);
    expect(find.text('Community content'), findsNothing);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsOneWidget);
    expect(find.text('Community rules and your content'), findsNothing);
  });

  testWidgets('Requires explicit agreement and server save before entry', (
    tester,
  ) async {
    final saved = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      app(
        load: () async => false,
        save: () {
          calls++;
          return saved.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsNothing);
    expect(find.text('Delete account'), findsOneWidget);
    await tester.tap(find.text('Agree and continue'));
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('accept-terms-checkbox')));
    await tester.pump();
    await tester.tap(find.text('Agree and continue'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Community content'), findsNothing);
    saved.complete();
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsOneWidget);
  });

  testWidgets('Save failure keeps community locked and permits retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        load: () async => false,
        save: () async {
          if (++calls == 1) throw StateError('offline');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept-terms-checkbox')));
    await tester.pump();
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsNothing);
    expect(
      find.text('Could not save your agreement. Please retry.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsOneWidget);
  });

  testWidgets('Existing acceptance opens community without another write', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        load: () async => true,
        save: () async {
          fail('Existing acceptance must not be rewritten');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsOneWidget);
  });

  testWidgets('Failed initial check stays locked and can be retried', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        load: () async {
          if (++calls == 1) throw StateError('offline');
          return true;
        },
        save: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsNothing);
    await tester.tap(find.text('Retry check'));
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsOneWidget);
  });

  testWidgets('Bundled terms are accessible before agreement', (tester) async {
    await tester.pumpWidget(app(load: () async => false, save: () async {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terms of Use'));
    await tester.pumpAndSettle();
    expect(find.byType(TermsDocumentScreen), findsOneWidget);
    expect(
      find.textContaining('These terms apply when you accept them.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Community content'), findsNothing);
  });
}
