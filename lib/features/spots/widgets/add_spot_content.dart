import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/features/community/chats/widgets/chat_thread_tile.dart'
    show GlobalSmallAvatar;
import 'package:ccs_app/features/community/groups/data/group_spot_access.dart'
    show maxSharedSpotGroups, memberSpotGroups;
import 'package:ccs_app/features/spots/controllers/add_spot_view_state.dart';

/// Renders reusable sections for AddSpotScreen.
class AddSpotContent implements AddSpotContentActions {
  final AddSpotViewState host;
  AddSpotContent(this.host);

  @override
  Widget temporaryAudiencePicker() => Material(
    type: MaterialType.transparency,
    child: Column(
      children: [
        if (host.groupVisibility) ...[
          CcsText(
            trText(
              memberSpotGroups.value.isEmpty
                  ? 'Join a group before creating a private event.'
                  : 'Select groups (up to 8)',
            ),
            style: const TextStyle(color: Colors.white70),
          ),
          for (final group in memberSpotGroups.value)
            CheckboxListTile(
              value: host.selectedGroupIds.contains(group.id),
              title: CcsText(group.name),
              secondary: GlobalSmallAvatar(
                avatarUrl: group.avatarUrl.isNotEmpty
                    ? group.avatarUrl
                    : group.photoUrl,
                username: group.name,
              ),
              onChanged: host.isSubmitting
                  ? null
                  : (value) => host.updateView(() {
                      if (value != true) {
                        host.selectedGroupIds.remove(group.id);
                      } else if (host.selectedGroupIds.length <
                          maxSharedSpotGroups) {
                        host.selectedGroupIds.add(group.id);
                      }
                    }),
            ),
        ],
      ],
    ),
  );
}
