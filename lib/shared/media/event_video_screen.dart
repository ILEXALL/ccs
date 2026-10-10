import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;
import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/core/platform/external_links.dart'
    show launchExternalUrl;
import 'social_video_link.dart';

Future<void> openEventVideo(BuildContext context, String url) async {
  final link = socialVideoLink(url);
  if (link == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: CcsText(
          communityText(
            en: 'Use an Instagram, TikTok or YouTube video link.',
            ru: 'Нужна ссылка на видео Instagram, TikTok или YouTube.',
            lv: 'Izmantojiet Instagram, TikTok vai YouTube video saiti.',
          ),
        ),
      ),
    );
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => EventVideoScreen(link: link)));
}

class EventVideoScreen extends StatefulWidget {
  const EventVideoScreen({super.key, required this.link});
  final SocialVideoLink link;
  @override
  State<EventVideoScreen> createState() => _EventVideoScreenState();
}

class _EventVideoScreenState extends State<EventVideoScreen>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  bool loading = true, failed = false;
  Uri? embed;
  Timer? timeout;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C111A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                failed = true;
                loading = false;
              });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.toString() == 'about:blank') {
              return NavigationDecision.navigate;
            }
            if (uri.scheme != 'https') return NavigationDecision.prevent;
            final h = uri.host.toLowerCase();
            final allowed = [
              'instagram.com',
              'tiktok.com',
              'youtube.com',
              'youtube-nocookie.com',
              'ccs-wine.vercel.app',
            ].any((host) => h == host || h.endsWith('.$host'));
            if (!allowed) return NavigationDecision.prevent;
            if (embed == null) {
              final resolved = socialVideoLink(request.url);
              if (resolved?.embed != null &&
                  resolved!.provider == widget.link.provider) {
                unawaited(loadEmbed(resolved.embed!));
                return NavigationDecision.prevent;
              }
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    if (widget.link.embed != null) {
      unawaited(loadEmbed(widget.link.embed!));
    } else {
      unawaited(controller.loadRequest(widget.link.original));
    }
    timeout = Timer(const Duration(seconds: 20), () {
      if (mounted && loading) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    });
  }

  Future<void> loadEmbed(Uri uri) async {
    embed = uri;
    final src = const HtmlEscape().convert(uri.toString());
    await controller.loadHtmlString(
      '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#0c111a"><iframe title="Video" src="$src" style="position:fixed;inset:0;width:100%;height:100%;border:0" allow="autoplay; encrypted-media; fullscreen; picture-in-picture" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>',
      baseUrl: 'https://ccs-wine.vercel.app/',
    );
  }

  bool suspended = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      suspended = true;
      unawaited(controller.loadRequest(Uri.parse('about:blank')));
    } else if (state == AppLifecycleState.resumed && suspended) {
      suspended = false;
      if (embed != null) {
        unawaited(loadEmbed(embed!));
      } else {
        unawaited(controller.loadRequest(widget.link.original));
      }
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0C111A),
    appBar: AppBar(
      title: CcsText(widget.link.label),
      backgroundColor: const Color(0xFF0C111A),
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: failed
                ? Center(
                    child: CcsText(
                      communityText(
                        en: 'Could not load this video.',
                        ru: 'Не удалось загрузить видео.',
                        lv: 'Neizdevās ielādēt video.',
                      ),
                    ),
                  )
                : WebViewWidget(controller: controller),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                CcsText(
                  communityText(
                    en: 'If playback is unavailable, open the original post.',
                    ru: 'Если видео недоступно, откройте оригинальную публикацию.',
                    lv: 'Ja video nav pieejams, atveriet oriģinālo ierakstu.',
                  ),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                TextButton.icon(
                  onPressed: () => launchExternalUrl(
                    context,
                    widget.link.original.toString(),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: CcsText(
                    communityText(
                      en: 'Open original',
                      ru: 'Открыть оригинал',
                      lv: 'Atvērt oriģinālu',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
