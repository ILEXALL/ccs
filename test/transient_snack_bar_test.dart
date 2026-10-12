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
