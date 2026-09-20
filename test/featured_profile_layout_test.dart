import 'package:ccs_app/main.dart' as app;
import 'package:ccs_app/achievements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('featured emblem stays avatar-sized and labels wrap below it', (tester) async {
    for(final size in [56.0,64.0]) {
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[SizedBox(width:size,height:size,child:const CircleAvatar()),const Expanded(child:Text('Driver')),app.FeaturedAchievementDisplay(emblemSize:size,language:'en',item:{'category':'attendance','tier':5,'status':'confirmed','title':{'en':'Event attendance','ru':'Посещение событий'}})]))));
      await tester.pumpAndSettle();
      final badge = find.byType(AchievementBadge);
      final fitted = find.ancestor(of:badge,matching:find.byType(FittedBox)).first;
      expect(tester.getSize(fitted),Size(size,size));
      expect(find.text('Event attendance'),findsOneWidget);
      expect(tester.getTopLeft(find.text('Event attendance')).dy,greaterThanOrEqualTo(tester.getBottomLeft(fitted).dy));
      expect(tester.takeException(),isNull);
    }
  });
}
