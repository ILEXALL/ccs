import 'package:ccs_app/spots_interaction_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget guide({
  bool hasCards = true,
  ScrollController? controller,
  VoidCallback? onAction,
}) => MaterialApp(
  home: _Harness(
    hasCards: hasCards,
    controller: controller,
    onAction: onAction,
  ),
);

class _Harness extends StatefulWidget {
  const _Harness({required this.hasCards, this.controller, this.onAction});
  final bool hasCards;
  final ScrollController? controller;
  final VoidCallback? onAction;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final categories = widget.controller ?? ScrollController();
  final cards = ScrollController();
  @override
  void dispose() {
    if (widget.controller == null) categories.dispose();
    cards.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: TextButton(
        onPressed: widget.onAction,
        child: const Text('Header action'),
      ),
    ),
    bottomNavigationBar: TextButton(
      onPressed: widget.onAction,
      child: const Text('Navigation action'),
    ),
    body: SpotsInteractionGuide(
      isVisible: true,
      hasCards: widget.hasCards,
      categoryController: categories,
      cardsController: cards,
      translate: (value) => value,
      categorySlider: SizedBox(
        height: 50,
        child: ListView(
          key: const ValueKey('categories'),
          controller: categories,
          scrollDirection: Axis.horizontal,
          children: List.generate(
            12,
            (index) => SizedBox(
              width: 100,
              child: TextButton(
                onPressed: widget.onAction,
                child: Text('Category $index'),
              ),
            ),
          ),
        ),
      ),
      cards: ListView(
        key: const ValueKey('cards'),
        controller: cards,
        children: List.generate(
          12,
          (index) => SizedBox(
            height: 200,
            child: TextButton(
              onPressed: widget.onAction,
              child: Text('Card $index'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('finishes each swipe before inertial scrolling stops', (
    tester,
  ) async {
    await tester.pumpWidget(guide());
    await tester.pumpAndSettle();
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    await tester.fling(
      find.byKey(const ValueKey('categories')),
      const Offset(-180, 0),
      2000,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();
    expect(state.categories.position.isScrollingNotifier.value, isTrue);
    expect(find.textContaining('2/2'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('cards')),
      const Offset(0, -180),
      2000,
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();
    expect(state.cards.position.isScrollingNotifier.value, isTrue);
    expect(find.textContaining('2/2'), findsNothing);
    expect(find.byKey(const ValueKey('spots-guide-barrier')), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        SpotsInteractionGuide.progressKey,
      ),
      2,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('short and cancelled swipes do not complete a step', (
    tester,
  ) async {
    await tester.pumpWidget(guide());
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('categories'));
    await tester.drag(target, const Offset(-25, 0), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(target));
    await gesture.moveBy(const Offset(-150, 0));
    await gesture.moveBy(const Offset(-80, 0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('spots-guide-barrier')), findsOneWidget);
  });

  testWidgets('blocks header, navigation, taps and the inactive scroll area', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(guide(onAction: () => actions++));
    await tester.pumpAndSettle();
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    for (final label in [
      'Header action',
      'Navigation action',
      'Category 0',
      'Card 0',
    ]) {
      await tester.tap(find.text(label), warnIfMissed: false);
    }
    await tester.drag(
      find.byKey(const ValueKey('cards')),
      const Offset(0, -150),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(actions, 0);
    expect(state.cards.offset, 0);
    expect(find.byKey(const ValueKey('spots-guide-barrier')), findsOneWidget);
    expect(
      ModalRoute.of(
        tester.element(find.byType(SpotsInteractionGuide)),
      )!.popDisposition,
      RoutePopDisposition.doNotPop,
    );
    await tester.drag(
      find.byKey(const ValueKey('categories')),
      const Offset(-180, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsOneWidget);
    final categoryOffset = state.categories.offset;
    await tester.drag(
      find.byKey(const ValueKey('categories')),
      const Offset(-180, 0),
      warnIfMissed: false,
    );
    await tester.tap(find.text('Card 0'), warnIfMissed: false);
    await tester.tap(find.text('Navigation action'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(state.categories.offset, categoryOffset);
    expect(actions, 0);
    await tester.drag(
      find.byKey(const ValueKey('cards')),
      const Offset(0, -180),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('spots-guide-barrier')), findsNothing);
    await tester.tap(find.text('Header action'));
    await tester.tap(find.text('Navigation action'));
    expect(actions, 2);
  });

  testWidgets('requires ordered real swipes and remembers completion', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(guide(controller: controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('categories')),
      warnIfMissed: false,
    );
    await tester.drag(
      find.byKey(const ValueKey('cards')),
      const Offset(0, -150),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('categories')),
      const Offset(-180, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('cards')),
      const Offset(0, -180),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        SpotsInteractionGuide.progressKey,
      ),
      2,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.pumpWidget(guide());
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsNothing);
    expect(find.textContaining('2/2'), findsNothing);
  });

  testWidgets('resumes the second step and waits for cards', (tester) async {
    SharedPreferences.setMockInitialValues({
      SpotsInteractionGuide.progressKey: 1,
    });
    await tester.pumpWidget(guide(hasCards: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsNothing);
    await tester.pumpWidget(guide());
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsOneWidget);
  });
}
