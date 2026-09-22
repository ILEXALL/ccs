import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material show Text;
import 'package:url_launcher/url_launcher.dart';
import 'package:ccs_app/core/localization/ccs_text.dart'
    show appTextStyle, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class _ChatLinkPart {
  final String text;
  final bool isLink;

  const _ChatLinkPart(this.text, {this.isLink = false});
}

final RegExp _chatLinkPattern = RegExp(
  r'''(?:(?:https?://|www\.)[^\s<>{}\[\]"']+|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}(?:[/?#][^\s<>{}\[\]"']*)?)''',
  caseSensitive: false,
);

String _trimChatLinkEnd(String value) {
  var result = value;

  while (result.isNotEmpty &&
      (result.endsWith('.') ||
          result.endsWith(',') ||
          result.endsWith('!') ||
          result.endsWith('?') ||
          result.endsWith(';') ||
          result.endsWith(':'))) {
    result = result.substring(0, result.length - 1);
  }

  int countCharacter(String source, String character) =>
      character.allMatches(source).length;

  while (result.endsWith(')') &&
      countCharacter(result, ')') > countCharacter(result, '(')) {
    result = result.substring(0, result.length - 1);
  }
  while (result.endsWith(']') &&
      countCharacter(result, ']') > countCharacter(result, '[')) {
    result = result.substring(0, result.length - 1);
  }
  while (result.endsWith('}') &&
      countCharacter(result, '}') > countCharacter(result, '{')) {
    result = result.substring(0, result.length - 1);
  }

  return result;
}

List<_ChatLinkPart> _chatLinkParts(String value) {
  if (value.isEmpty) {
    return const <_ChatLinkPart>[];
  }

  final parts = <_ChatLinkPart>[];
  var cursor = 0;

  for (final match in _chatLinkPattern.allMatches(value)) {
    final rawMatch = match.group(0) ?? '';
    if (rawMatch.isEmpty) {
      continue;
    }

    // Do not turn the domain portion of an email address into a web link.
    if (match.start > 0 && value[match.start - 1] == '@') {
      continue;
    }

    final linkText = _trimChatLinkEnd(rawMatch);
    if (linkText.isEmpty) {
      continue;
    }

    if (match.start > cursor) {
      parts.add(_ChatLinkPart(value.substring(cursor, match.start)));
    }

    parts.add(_ChatLinkPart(linkText, isLink: true));

    final trailingStart = match.start + linkText.length;
    if (trailingStart < match.end) {
      parts.add(_ChatLinkPart(value.substring(trailingStart, match.end)));
    }

    cursor = match.end;
  }

  if (cursor < value.length) {
    parts.add(_ChatLinkPart(value.substring(cursor)));
  }

  if (parts.isEmpty) {
    parts.add(_ChatLinkPart(value));
  }

  return parts;
}

Uri? _chatLinkUri(String value) {
  final clean = value.trim();
  if (clean.isEmpty) {
    return null;
  }

  final normalized = clean.startsWith('http://') || clean.startsWith('https://')
      ? clean
      : 'https://$clean';
  final uri = Uri.tryParse(normalized);

  if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
    return null;
  }

  return uri;
}

Future<void> _openChatLink(BuildContext context, String value) async {
  final uri = _chatLinkUri(value);
  if (uri == null) {
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: material.Text('Could not open link.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: material.Text('Could not open link.')),
      );
    }
  }
}

class ChatLinkText extends StatefulWidget {
  final String text;
  final Color linkColor;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;

  const ChatLinkText(
    this.text, {
    super.key,
    this.linkColor = blue,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
  });

  @override
  State<ChatLinkText> createState() => _ChatLinkTextState();
}

class _ChatLinkTextState extends State<ChatLinkText> {
  final Map<int, TapGestureRecognizer> _recognizers = {};

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void didUpdateWidget(covariant ChatLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedText = trText(widget.text);
    final parts = _chatLinkParts(displayedText);
    final baseStyle = appTextStyle(widget.style);

    final spans = <InlineSpan>[];
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      if (!part.isLink) {
        spans.add(TextSpan(text: part.text));
        continue;
      }

      final recognizer = _recognizers.putIfAbsent(
        index,
        () => TapGestureRecognizer(),
      );
      recognizer.onTap = () => unawaited(_openChatLink(context, part.text));

      spans.add(
        TextSpan(
          text: part.text,
          style: (baseStyle ?? const TextStyle()).copyWith(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor,
          ),
          recognizer: recognizer,
        ),
      );
    }

    return material.Text.rich(
      TextSpan(style: baseStyle, children: spans),
      textAlign: widget.textAlign,
      softWrap: widget.softWrap,
      overflow: widget.overflow,
      maxLines: widget.maxLines,
    );
  }
}
