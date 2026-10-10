import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/features/spots/widgets/spot_review_card.dart'
    show SpotReviewCard;
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart'
    show CcsText, LanguageReactiveState, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/community/chats/widgets/mention_text_field.dart'
    show MentionTextField;
import 'package:ccs_app/features/spots/data/spot_reviews.dart'
    show
        SpotCommentsCacheEntry,
        removeSpotReviewFromSessionCache,
        saveSpotReview,
        spotCommentsPageSize,
        spotCommentsSessionCache,
        spotReviewActionErrorMessage;
import 'package:ccs_app/features/spots/models/spot_review_identity.dart'
    show spotReviewKey;
import 'package:ccs_app/core/firestore/collections.dart'
    show spotReviewsCollection;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;
import 'package:ccs_app/features/spots/models/spot_review.dart'
    show SpotReviewData;

class SpotReviewsSection extends StatefulWidget {
  final CarSpot spot;

  const SpotReviewsSection({super.key, required this.spot});

  @override
  State<SpotReviewsSection> createState() => _SpotReviewsSectionState();
}

class _SpotReviewsSectionState extends State<SpotReviewsSection>
    with LanguageReactiveState {
  final commentController = TextEditingController();
  final List<SpotReviewData> reviews = [];
  DocumentSnapshot<Map<String, dynamic>>? lastReviewDocument;
  bool isSaving = false;
  bool isLoadingReviews = false;
  bool hasMoreReviews = true;
  bool useCommentsFallbackQuery = false;
  Object? reviewsError;

  @override
  void initState() {
    super.initState();
    if (!restoreReviewsFromSessionCache()) {
      unawaited(loadReviews(reset: true));
    }
  }

  @override
  void didUpdateWidget(SpotReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (spotReviewKey(oldWidget.spot) != spotReviewKey(widget.spot)) {
      reviews.clear();
      lastReviewDocument = null;
      hasMoreReviews = true;
      useCommentsFallbackQuery = false;
      reviewsError = null;
      if (!restoreReviewsFromSessionCache()) {
        unawaited(loadReviews(reset: true));
      }
    }
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  bool restoreReviewsFromSessionCache() {
    final spotId = spotReviewKey(widget.spot);
    final cached = spotCommentsSessionCache[spotId];

    if (cached == null || !cached.isFresh) {
      return false;
    }

    reviews
      ..clear()
      ..addAll(cached.reviews);
    lastReviewDocument = cached.lastDocument;
    hasMoreReviews = cached.hasMoreReviews;
    useCommentsFallbackQuery = cached.useFallbackQuery;
    reviewsError = null;
    return true;
  }

  void saveReviewsToSessionCache() {
    final spotId = spotReviewKey(widget.spot);
    spotCommentsSessionCache[spotId] = SpotCommentsCacheEntry(
      reviews: List<SpotReviewData>.unmodifiable(reviews),
      lastDocument: lastReviewDocument,
      hasMoreReviews: hasMoreReviews,
      useFallbackQuery: useCommentsFallbackQuery,
      cachedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> loadReviews({bool reset = false}) async {
    if (isLoadingReviews || (!reset && !hasMoreReviews)) {
      return;
    }

    if (mounted) {
      setState(() {
        isLoadingReviews = true;
        if (reset) {
          reviewsError = null;
        }
      });
    }

    Future<QuerySnapshot<Map<String, dynamic>>> loadSnapshot({
      required bool withTypeFilter,
      required String label,
    }) {
      Query<Map<String, dynamic>> query = spotReviewsCollection().where(
        'spotId',
        isEqualTo: spotReviewKey(widget.spot),
      );

      if (withTypeFilter) {
        query = query.where('type', isEqualTo: 'comment');
      }

      query = query.limit(
        withTypeFilter ? spotCommentsPageSize : spotCommentsPageSize * 3,
      );

      if (!reset && lastReviewDocument != null) {
        query = query.startAfterDocument(lastReviewDocument!);
      }

      return query.debugGet(null, label);
    }

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      var snapshotUsedFallback = useCommentsFallbackQuery;
      try {
        snapshot = await loadSnapshot(
          withTypeFilter: !useCommentsFallbackQuery,
          label: reset
              ? 'spot comments first page get'
              : 'spot comments next page get',
        );
      } on FirebaseException catch (error) {
        if (error.code != 'failed-precondition') {
          rethrow;
        }

        useCommentsFallbackQuery = true;
        snapshotUsedFallback = true;
        snapshot = await loadSnapshot(
          withTypeFilter: false,
          label: reset
              ? 'spot comments first page fallback get'
              : 'spot comments next page fallback get',
        );
      }

      final nextReviews = snapshot.docs
          .map((doc) => SpotReviewData.fromFirestore(doc))
          .where((review) => review.comment.trim().isNotEmpty)
          .take(spotCommentsPageSize)
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        if (reset) {
          reviews.clear();
        }
        reviews.addAll(nextReviews);
        if (snapshot.docs.isNotEmpty) {
          lastReviewDocument = snapshot.docs.last;
        }
        hasMoreReviews =
            snapshot.docs.length ==
            (snapshotUsedFallback
                ? spotCommentsPageSize * 3
                : spotCommentsPageSize);
        reviewsError = null;
        isLoadingReviews = false;
      });
      saveReviewsToSessionCache();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        reviewsError = error;
        isLoadingReviews = false;
      });
    }
  }

  Future<void> submitComment() async {
    final comment = commentController.text.trim();

    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
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
    setState(() => isSaving = true);

    try {
      final review = await saveSpotReview(spot: widget.spot, comment: comment);

      if (!mounted) {
        return;
      }

      commentController.clear();
      setState(() {
        reviews.removeWhere((item) => item.id == review.id);
        reviews.insert(0, review);
      });
      saveReviewsToSessionCache();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: blue,
          content: CcsText(
            'Comment posted.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
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
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleCommentCount = math.max(
      widget.spot.commentCount,
      reviews.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CcsText(
              'Comments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            CcsText(
              visibleCommentCount == 0
                  ? '0 comments'
                  : '$visibleCommentCount ${visibleCommentCount == 1 ? 'comment' : 'comments'}',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (widget.spot.isTemporary)
          MentionTextField(
            controller: commentController,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: trText('Write a comment'),
              hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF142232),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFF2A4058)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: Color(0xFF2A4058)),
              ),
              suffixIcon: IconButton(
                tooltip: trText('Post Comment'),
                onPressed: isSaving ? null : submitComment,
                icon: Icon(
                  isSaving ? Icons.hourglass_bottom : Icons.send_rounded,
                  color: const Color(0xFF73BFFF),
                ),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MentionTextField(
                  controller: commentController,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: widget.spot.isTemporary
                        ? communityText(
                            en: 'Write a comment about this event',
                            ru: 'Напишите комментарий о событии',
                            lv: 'Rakstiet komentāru par šo pasākumu',
                          )
                        : trText('Write a comment about this spot'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: blue),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : submitComment,
                    icon: Icon(isSaving ? Icons.hourglass_bottom : Icons.send),
                    label: CcsText(isSaving ? 'Saving...' : 'Post Comment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (reviewsError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CcsText(
                  'Could not load comments.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                CcsText(
                  '$reviewsError',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => loadReviews(reset: reviews.isEmpty),
                  icon: const Icon(Icons.refresh),
                  label: const CcsText('Retry'),
                ),
              ],
            ),
          )
        else if (reviews.isEmpty && isLoadingReviews)
          const Center(child: CircularProgressIndicator(color: blue))
        else if (reviews.isEmpty && widget.spot.isTemporary)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: CcsText(
              communityText(
                en: 'Start the conversation.',
                ru: 'Начните обсуждение.',
                lv: 'Sāciet sarunu.',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else if (reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: CcsText(
              widget.spot.isTemporary
                  ? communityText(
                      en: 'No comments yet. Start the conversation.',
                      ru: 'Комментариев пока нет. Начните обсуждение.',
                      lv: 'Vēl nav komentāru. Sāciet sarunu.',
                    )
                  : 'No comments yet. Be the first to comment on this spot.',
              style: const TextStyle(color: Colors.white54),
            ),
          )
        else
          for (final review in reviews) ...[
            SpotReviewCard(
              spot: widget.spot,
              review: review,
              onDeleted: () {
                setState(() {
                  reviews.removeWhere((item) => item.id == review.id);
                });
                removeSpotReviewFromSessionCache(
                  spotReviewKey(widget.spot),
                  review.id,
                );
                saveReviewsToSessionCache();
              },
            ),
            const SizedBox(height: 10),
          ],
        if (hasMoreReviews && reviews.isNotEmpty) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: isLoadingReviews
                  ? null
                  : () => unawaited(loadReviews()),
              icon: isLoadingReviews
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : const Icon(Icons.expand_more),
              label: CcsText(isLoadingReviews ? 'Loading...' : 'More comments'),
              style: OutlinedButton.styleFrom(
                foregroundColor: blue,
                side: const BorderSide(color: blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
