import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_background.dart' show appPageRoute;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;

class ChatPhotoViewerScreen extends StatelessWidget {
  final String imageUrl;

  const ChatPhotoViewerScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: CcsText(trText('Photo')),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) {
              return const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 44,
              );
            },
          ),
        ),
      ),
    );
  }
}

class ChatAttachmentImage extends StatelessWidget {
  final String imageUrl;
  final bool mine;

  const ChatAttachmentImage({
    super.key,
    required this.imageUrl,
    this.mine = false,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();
    if (cleanUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          appPageRoute(
            builder: (_) => ChatPhotoViewerScreen(imageUrl: cleanUrl),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 160,
            maxWidth: 270,
            maxHeight: 340,
          ),
          child: Image.network(
            cleanUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }

              return Container(
                width: 220,
                height: 180,
                alignment: Alignment.center,
                color: Colors.white.withValues(alpha: mine ? 0.10 : 0.06),
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: blue, strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (context, error, stack) {
              return Container(
                width: 220,
                height: 150,
                alignment: Alignment.center,
                color: Colors.white.withValues(alpha: 0.06),
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget stagedChatPhotoPreview({
  required String localPhotoPath,
  required VoidCallback onRemove,
  bool isBusy = false,
}) {
  final cleanPath = localPhotoPath.trim();
  if (cleanPath.isEmpty) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: blue.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(cleanPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                      ),
                    );
                  },
                ),
                if (isBusy)
                  Container(
                    color: Colors.black.withValues(alpha: 0.42),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: blue,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: InkWell(
              onTap: isBusy ? null : onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 17),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
