import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/main.dart' as app;

void main() {
  test('old topics have no gallery and malformed URLs are ignored', () {
    expect(app.forumTopicPhotos({}), isEmpty);
    expect(
      app.forumTopicPhotos({
        'photoUrls': [
          'https://example.com/1.jpg',
          'file:///private',
          'https://example.com/2.jpg',
        ],
      }),
      ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );
  });
  test(
    'topic creation rejects more than four attachments before saving',
    () async {
      await expectLater(
        app.createForumTopic(
          title: 'Title',
          category: 'general',
          description: 'Description',
          avatarUrl: '',
          photoUrls: List.filled(5, 'https://example.com/p.jpg'),
        ),
        throwsArgumentError,
      );
    },
  );
  testWidgets('topic photos swipe and open the same full-screen zoom gallery', (
    tester,
  ) async {
    const sources = [
      'local:missing-photo-one.jpg',
      'local:missing-photo-two.jpg',
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: app.SpotPhotoCarousel.photos(sources: sources, height: 220),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.byType(PageView));
    await tester.pumpAndSettle();
    expect(find.byType(app.SpotPhotoGalleryScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    final gallery = find.descendant(
      of: find.byType(app.SpotPhotoGalleryScreen),
      matching: find.byType(PageView),
    );
    await tester.drag(gallery, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
