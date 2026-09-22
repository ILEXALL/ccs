import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Text;

final Map<String, int> forumReplyCountCache = <String, int>{};

final Map<String, Future<int>> _forumReplyCountLoads = <String, Future<int>>{};

Future<int> fetchAccurateForumReplyCount(
  String topicId,
  int fallbackCount,
) async {
  final cleanTopicId = topicId.trim();
  if (cleanTopicId.isEmpty) {
    return math.max(0, fallbackCount);
  }

  final cached = forumReplyCountCache[cleanTopicId];
  if (cached != null) {
    return cached;
  }

  final existingLoad = _forumReplyCountLoads[cleanTopicId];
  if (existingLoad != null) {
    return existingLoad;
  }

  final load = () async {
    try {
      final aggregate = await FirebaseFirestore.instance
          .collection('forum_topics')
          .doc(cleanTopicId)
          .collection('replies')
          .count()
          .get();

      final actualCount = aggregate.count ?? 0;
      forumReplyCountCache[cleanTopicId] = actualCount;
      return actualCount;
    } catch (error) {
      debugPrint('Could not load accurate forum reply count: $error');
      return math.max(0, fallbackCount);
    }
  }();

  _forumReplyCountLoads[cleanTopicId] = load;
  try {
    return await load;
  } finally {
    if (identical(_forumReplyCountLoads[cleanTopicId], load)) {
      _forumReplyCountLoads.remove(cleanTopicId);
    }
  }
}

void invalidateForumReplyCount(String topicId) {
  final cleanTopicId = topicId.trim();
  if (cleanTopicId.isEmpty) return;
  forumReplyCountCache.remove(cleanTopicId);
  _forumReplyCountLoads.remove(cleanTopicId);
}
