import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/features/community/chats/models/chat_thread.dart'
    show ChatThreadData;
import 'package:ccs_app/features/moderation/data/regional_access.dart'
    show currentUserCanModerateSpot;
import 'package:ccs_app/features/spots/models/car_spot.dart' show CarSpot;

const maxSharedSpotGroups = 8;

final memberSpotGroups = ValueNotifier<List<ChatThreadData>>([]);

final Map<String, Set<String>> groupSpotIds = {};

bool canViewGroupSpot(CarSpot spot) =>
    !spot.isGroupSpot ||
    currentUserCanModerateSpot(spot) ||
    memberSpotGroups.value.any(
      (group) => spot.sharedGroupIds.contains(group.id),
    );
