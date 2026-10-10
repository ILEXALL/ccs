enum SocialVideoProvider { instagram, tiktok, youtube }

class SocialVideoLink {
  const SocialVideoLink(this.provider, this.original, this.embed);
  final SocialVideoProvider provider;
  final Uri original;
  final Uri? embed;
  String get label => switch (provider) {
    SocialVideoProvider.instagram => 'Instagram',
    SocialVideoProvider.tiktok => 'TikTok',
    SocialVideoProvider.youtube => 'YouTube',
  };
}

SocialVideoLink? socialVideoLink(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final original = uri.replace(scheme: 'https');
  if ([
    'instagram.com',
    'www.instagram.com',
    'm.instagram.com',
  ].contains(host)) {
    if (parts.length >= 2 &&
        ['reel', 'reels', 'p', 'tv'].contains(parts[0]) &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[1])) {
      return SocialVideoLink(
        SocialVideoProvider.instagram,
        original,
        Uri.https(
          'www.instagram.com',
          '/${parts[0] == 'reels' ? 'reel' : parts[0]}/${parts[1]}/embed/',
        ),
      );
    }
    if (parts.isNotEmpty && parts.first == 'share') {
      return SocialVideoLink(SocialVideoProvider.instagram, original, null);
    }
    return null;
  }
  if ([
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
    'www.youtube-nocookie.com',
  ].contains(host)) {
    String? id;
    if (host == 'youtu.be' && parts.isNotEmpty) {
      id = parts.first;
    } else if (parts.isNotEmpty && parts.first == 'watch')
      id = uri.queryParameters['v'];
    else if (parts.length >= 2 &&
        ['shorts', 'embed', 'live'].contains(parts.first))
      id = parts[1];
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return null;
    return SocialVideoLink(
      SocialVideoProvider.youtube,
      original,
      Uri.https('www.youtube.com', '/embed/$id', {
        'playsinline': '1',
        'autoplay': '0',
      }),
    );
  }
  if ([
    'tiktok.com',
    'www.tiktok.com',
    'm.tiktok.com',
    'vm.tiktok.com',
    'vt.tiktok.com',
  ].contains(host)) {
    final index = parts.indexOf('video');
    final id = index >= 0 && index + 1 < parts.length ? parts[index + 1] : null;
    if (id != null && RegExp(r'^\d+$').hasMatch(id)) {
      return SocialVideoLink(
        SocialVideoProvider.tiktok,
        original,
        Uri.https('www.tiktok.com', '/player/v1/$id', {'autoplay': '0'}),
      );
    }
    if (host == 'vm.tiktok.com' ||
        host == 'vt.tiktok.com' ||
        (parts.isNotEmpty && parts.first == 't')) {
      return SocialVideoLink(SocialVideoProvider.tiktok, original, null);
    }
  }
  return null;
}
