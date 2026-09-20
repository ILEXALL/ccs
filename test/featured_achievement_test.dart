import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  for (final earned in [true,false]) {
    testWidgets('profile display action requires an earned achievement: $earned', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(home: AchievementsScreen(language:'en', selectForProfile: (id) async {selected=id;}, load: () async => {'enabled':true,'items':[{'id':'spots.1','category':'spots','title':{'en':'Spots'},'xp':25,'threshold':1,'progress':1,'tier':1,'available':true,'status':earned?'confirmed':'locked'}]})));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('achievement-tile-spots.1')));
      await tester.pumpAndSettle();
      expect(find.text('Display on profile'), earned ? findsOneWidget : findsNothing);
      if(earned) {
        await tester.ensureVisible(find.text('Display on profile'));
        await tester.tap(find.text('Display on profile'));
        await tester.pumpAndSettle();
        expect(selected,'spots.1');
      }
      expect(tester.takeException(),isNull);
    });
  }
}
