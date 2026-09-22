import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/firebase_values.dart'
    show stringFromFirebase;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue, panelGlass;
import 'package:ccs_app/features/auth/data/auth_state.dart' show currentUser;
import 'package:ccs_app/features/community/forum/models/forum_categories.dart'
    show forumCategoryIdFromFirebase, forumCategoryTitle;
import 'package:ccs_app/features/moderation/data/forum_review.dart'
    show approveForumTopic;
import 'package:ccs_app/features/moderation/data/forum_review_lease.dart'
    show ForumReviewLease;
import 'package:ccs_app/features/moderation/widgets/forum_actions.dart'
    show showRejectForumTopicDialog;
import 'package:ccs_app/shared/models/user_role.dart' show userRoleIsStaff;

class ForumModerationScreen extends StatefulWidget {
  final ForumReviewLease Function()? leaseFactory;
  const ForumModerationScreen({super.key, this.leaseFactory});
  @override
  State<ForumModerationScreen> createState() => _ForumModerationScreenState();
}

class _ForumModerationScreenState extends State<ForumModerationScreen>
    with WidgetsBindingObserver {
  ForumReviewLease? _lease;
  bool _opening = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && userRoleIsStaff(currentUser.role)) _openReview();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _closeLease() {
    final old = _lease;
    _lease = null;
    old?.removeListener(_changed);
    old?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeLease();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lease = _lease;
    if (lease == null) return;
    if (state == AppLifecycleState.resumed) {
      // Returning requires explicitly reopening review.
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      lease.suspend();
      unawaited(lease.release());
    }
  }

  Future<void> _openReview() async {
    if (_opening) return;
    _closeLease();
    final lease = (widget.leaseFactory?.call() ?? ForumReviewLease());
    _lease = lease;
    lease.addListener(_changed);
    setState(() {
      _opening = true;
      _error = '';
    });
    try {
      await lease.acquire();
    } catch (error) {
      lease.markLost(error: error, opening: true);
    } finally {
      if (mounted)
        setState(() {
          _opening = false;
        });
    }
  }

  Future<void> _decide(String topicId, bool approve) async {
    final lease = _lease;
    if (lease == null || !lease.active || lease.busy) return;
    try {
      await lease.runAction(() async {
        if (approve) {
          await approveForumTopic(topicId, lease);
        } else {
          await showRejectForumTopicDialog(context, topicId, lease);
        }
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = 'Could not complete review: $error';
        });
    }
  }

  Widget _topicTile(Map<String, dynamic> topic) {
    final topicId = stringFromFirebase(topic['id'], '');
    final title = stringFromFirebase(topic['title'], trText('Untitled topic'));
    final enabled = _lease?.active == true && _lease?.busy == false;
    return Card(
      color: panelGlass,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CcsText(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            CcsText(
              '@${stringFromFirebase(topic['authorName'], 'ccs_driver')}',
              style: const TextStyle(color: Colors.white70),
            ),
            CcsText(
              forumCategoryTitle(
                forumCategoryIdFromFirebase(
                  topic['categoryId'] ?? topic['category'],
                ),
              ),
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            CcsText(
              stringFromFirebase(topic['description'], ''),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? () => _decide(topicId, false) : null,
                    icon: const Icon(Icons.close),
                    label: CcsText(trText('Reject')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: enabled ? () => _decide(topicId, true) : null,
                    icon: const Icon(Icons.check),
                    label: CcsText(trText('Approve')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lease = _lease;
    final active = lease?.active == true;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: CcsText(trText('Forum review')),
        foregroundColor: blue,
        backgroundColor: Colors.transparent,
        actions: [
          if (active)
            IconButton(
              tooltip: trText('Refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: lease!.busy
                  ? null
                  : () async {
                      try {
                        await lease.renew();
                      } catch (_) {}
                    },
            ),
        ],
      ),
      body: !userRoleIsStaff(currentUser.role)
          ? const Center(
              child: CcsText(
                'No access',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_opening)
                    const Center(child: CircularProgressIndicator()),
                  if (!_opening && !active) ...[
                    if (lease?.reviewerUsername.isNotEmpty ?? false)
                      CcsText(
                        'Forum review is currently being checked by @${lease!.reviewerUsername}. You have shared topics awaiting review.',
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    if (lease?.errorText.isNotEmpty ?? false)
                      CcsText(
                        trText(lease!.errorText),
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ElevatedButton(
                      onPressed: _openReview,
                      child: CcsText(trText('Try again')),
                    ),
                  ],
                  if (_error.isNotEmpty)
                    CcsText(
                      _error,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  if (active)
                    Expanded(
                      child: lease!.topics.isEmpty
                          ? Center(
                              child: CcsText(
                                trText('No topics awaiting review'),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            )
                          : ListView(
                              children: lease.topics.map(_topicTile).toList(),
                            ),
                    ),
                ],
              ),
            ),
    );
  }
}
