import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText;

Uri? normalizedExternalUri(String rawUrl, {String? kind}) {
  final trimmedUrl = rawUrl.trim();

  if (trimmedUrl.isEmpty) {
    return null;
  }

  final parsed = Uri.tryParse(trimmedUrl);

  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }

  final cleanKind = (kind ?? '').trim().toLowerCase();
  final lower = trimmedUrl.toLowerCase();

  if (cleanKind == 'telegram') {
    var handle = trimmedUrl;
    handle = handle.startsWith('@') ? handle.substring(1) : handle;
    handle = handle.replaceFirst(
      RegExp(r'^(www\.)?(t\.me|telegram\.me)/?'),
      '',
    );
    handle = handle.replaceAll(RegExp(r'^/+'), '');
    return Uri.https('t.me', handle.isEmpty ? '/' : '/$handle');
  }

  if (cleanKind == 'tiktok') {
    var handle = trimmedUrl;
    handle = handle.startsWith('@') ? handle.substring(1) : handle;
    handle = handle.replaceFirst(RegExp(r'^(www\.)?tiktok\.com/?'), '');
    handle = handle.replaceAll(RegExp(r'^/+'), '');
    final path = handle.startsWith('@') ? handle : '@$handle';
    return Uri.https('www.tiktok.com', handle.isEmpty ? '/' : '/$path');
  }

  if (cleanKind == 'instagram' ||
      (cleanKind.isEmpty && lower.startsWith('@')) ||
      lower.startsWith('instagram.com/') ||
      lower.startsWith('www.instagram.com/')) {
    return instagramContactUri(trimmedUrl);
  }

  if (lower.startsWith('www.') ||
      lower.startsWith('t.me/') ||
      lower.startsWith('telegram.me/') ||
      lower.startsWith('tiktok.com/') ||
      lower.startsWith('instagram.com/')) {
    return Uri.tryParse('https://$trimmedUrl');
  }

  return null;
}

Future<void> launchExternalUrl(
  BuildContext context,
  String rawUrl, {
  String? kind,
}) async {
  final trimmedUrl = rawUrl.trim();

  if (trimmedUrl.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'No link added for this spot.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final uri = normalizedExternalUri(trimmedUrl, kind: kind);

  if (uri == null || !uri.hasScheme) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'This link is not valid yet.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
    return;
  }

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'Could not open this link.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Uri instagramContactUri(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);

  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }

  var handle = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  handle = handle.replaceFirst(RegExp(r'^(www\.)?instagram\.com/?'), '');
  handle = handle.replaceAll(RegExp(r'^/+'), '');

  return Uri.https('instagram.com', handle.isEmpty ? '/' : '/$handle');
}

Future<void> launchContactUri(BuildContext context, Uri uri) async {
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: CcsText(
          'Could not open this contact.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
