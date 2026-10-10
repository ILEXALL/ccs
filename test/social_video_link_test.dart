import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/shared/media/social_video_link.dart';

void main() {
  test('YouTube watch, Shorts and share URLs use official embedded player', () {
    for (final url in [
      'https://youtu.be/dQw4w9WgXcQ?si=abc',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/shorts/dQw4w9WgXcQ',
    ]) {
      final link = socialVideoLink(url)!;
      expect(link.provider, SocialVideoProvider.youtube);
      expect(link.embed!.path, '/embed/dQw4w9WgXcQ');
      expect(link.embed!.queryParameters['autoplay'], '0');
    }
  });
  test('Instagram and TikTok canonical links map to provider embeds', () {
    expect(
      socialVideoLink(
        'https://www.instagram.com/reel/Ab_cd123/?igsh=123',
      )!.embed!.path,
      '/reel/Ab_cd123/embed/',
    );
    expect(
      socialVideoLink(
        'https://www.tiktok.com/@user/video/6718335390845095173',
      )!.embed!.path,
      '/player/v1/6718335390845095173',
    );
  });
  test('short share links remain in-app for provider redirect resolution', () {
    for (final url in [
      'https://vm.tiktok.com/ABC/',
      'https://vt.tiktok.com/DEF/',
      'https://www.instagram.com/share/reel/ABC',
    ]) {
      expect(socialVideoLink(url), isNotNull);
      expect(socialVideoLink(url)!.embed, isNull);
    }
  });
  test(
    'reject direct files, unrelated hosts, unsafe schemes and malformed ids',
    () {
      for (final url in [
        'https://example.com/video.mp4',
        'javascript:alert(1)',
        'https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ',
        'https://user@youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=bad',
        'https://instagram.com/profile',
      ]) {
        expect(socialVideoLink(url), isNull, reason: url);
      }
    },
  );
}
