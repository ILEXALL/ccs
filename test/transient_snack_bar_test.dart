import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/shared/widgets/transient_snack_bar.dart';

void main() {
  testWidgets('submission message expires even while another route covers it', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showTransientSnackBar(
      context,
      const SnackBar(
        content: Text('Spot added'),
        duration: Duration(seconds: 3),
        persist: false,
        showCloseIcon: true,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Map')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(find.text('Spot added'), findsNothing);
  });

  testWidgets('close works after switching tabs with animations disabled', (
    tester,
  ) async {
    late BuildContext context;
    var tab = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, setState) {
            context = c;
            update = setState;
            return TickerMode(
              enabled: false,
              child: Scaffold(
                body: IndexedStack(
                  index: tab,
                  children: const [Text('Create'), Text('Map')],
                ),
              ),
            );
          },
        ),
      ),
    );
    showTransientSnackBar(
      context,
      const SnackBar(
        content: Text('Published'),
        duration: Duration(seconds: 3),
      ),
    );
    update(() => tab = 1);
    await tester.pump();
    expect(find.text('Published'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Published'), findsNothing);
    showTransientSnackBar(
      context,
      const SnackBar(
        content: Text('Published again'),
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Published again'), findsNothing);
  });

  testWidgets('old timeout cannot remove a newer snackbar', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showTransientSnackBar(
      context,
      const SnackBar(content: Text('First'), duration: Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New message'),
        duration: Duration(seconds: 20),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('New message'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
