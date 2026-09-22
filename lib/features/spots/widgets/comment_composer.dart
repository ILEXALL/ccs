import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/spots/data/spot_reviews.dart'
    show saveSpotReview, spotReviewActionErrorMessage;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

class SpotCommentComposerSheet extends StatefulWidget {
  final CarSpot spot;
  final ScaffoldMessengerState? messenger;

  const SpotCommentComposerSheet({
    super.key,
    required this.spot,
    required this.messenger,
  });

  @override
  State<SpotCommentComposerSheet> createState() =>
      _SpotCommentComposerSheetState();
}

class _SpotCommentComposerSheetState extends State<SpotCommentComposerSheet>
    with LanguageReactiveState {
  late final TextEditingController controller;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void showMessage(SnackBar snackBar) {
    final messenger = widget.messenger;
    if (messenger == null) {
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
  }

  Future<void> submitComment() async {
    final comment = controller.text.trim();

    if (comment.isEmpty) {
      showMessage(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            'Write a comment first.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    if (isSaving) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (mounted) {
      setState(() => isSaving = true);
    }

    try {
      await saveSpotReview(spot: widget.spot, comment: comment);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        showMessage(
          const SnackBar(
            backgroundColor: blue,
            content: CcsText(
              'Comment posted.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      showMessage(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: CcsText(
            spotReviewActionErrorMessage(
              error,
              fallback: 'Could not save comment.',
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CcsText(
                    'Comment ${widget.spot.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(context).pop();
                        },
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: false,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: trText('Write a comment'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: blue),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isSaving ? null : submitComment,
                icon: Icon(isSaving ? Icons.hourglass_top : Icons.send),
                label: CcsText(isSaving ? 'Posting...' : 'Post Comment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
