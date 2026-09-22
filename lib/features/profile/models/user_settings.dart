import 'package:ccs_app/core/firestore/firebase_values.dart'
    show boolFromFirebase, mapFromFirebase, stringFromFirebase;

class UserSettingsData {
  final String instagram;
  final String tiktok;
  final String telegram;
  final bool reviewNotifications;
  final bool likeNotifications;
  final bool commentNotifications;
  final bool newSpotNotifications;
  final bool newMessageNotifications;
  final bool xpNotifications;
  final bool friendAtSpotNotifications;
  final bool friendLiveShareNotifications;
  final bool publicProfile;
  final bool showGarage;

  const UserSettingsData({
    required this.instagram,
    required this.tiktok,
    required this.telegram,
    required this.reviewNotifications,
    required this.likeNotifications,
    required this.commentNotifications,
    required this.newSpotNotifications,
    this.newMessageNotifications = true,
    this.xpNotifications = true,
    this.friendAtSpotNotifications = true,
    this.friendLiveShareNotifications = true,
    required this.publicProfile,
    required this.showGarage,
  });

  factory UserSettingsData.fromFirebase(Object? value) {
    final data = mapFromFirebase(value);
    final defaults = defaultUserSettings();

    return UserSettingsData(
      instagram: stringFromFirebase(data['instagram'], defaults.instagram),
      tiktok: stringFromFirebase(data['tiktok'], defaults.tiktok),
      telegram: stringFromFirebase(data['telegram'], defaults.telegram),
      reviewNotifications: boolFromFirebase(
        data['reviewNotifications'],
        defaults.reviewNotifications,
      ),
      likeNotifications: boolFromFirebase(
        data['likeNotifications'],
        defaults.likeNotifications,
      ),
      commentNotifications: boolFromFirebase(
        data['commentNotifications'],
        defaults.commentNotifications,
      ),
      newSpotNotifications: boolFromFirebase(
        data['newSpotNotifications'],
        defaults.newSpotNotifications,
      ),
      newMessageNotifications: boolFromFirebase(
        data['newMessageNotifications'],
        defaults.newMessageNotifications,
      ),
      xpNotifications: boolFromFirebase(
        data['xpNotifications'],
        defaults.xpNotifications,
      ),
      friendAtSpotNotifications: boolFromFirebase(
        data['friendAtSpotNotifications'],
        defaults.friendAtSpotNotifications,
      ),
      friendLiveShareNotifications: boolFromFirebase(
        data['friendLiveShareNotifications'],
        defaults.friendLiveShareNotifications,
      ),
      publicProfile: boolFromFirebase(
        data['publicProfile'],
        defaults.publicProfile,
      ),
      showGarage: boolFromFirebase(data['showGarage'], defaults.showGarage),
    );
  }

  Map<String, Object?> toFirebase() {
    return {
      'instagram': instagram,
      'tiktok': tiktok,
      'telegram': telegram,
      'reviewNotifications': reviewNotifications,
      'likeNotifications': likeNotifications,
      'commentNotifications': commentNotifications,
      'newSpotNotifications': newSpotNotifications,
      'newMessageNotifications': newMessageNotifications,
      'xpNotifications': xpNotifications,
      'friendAtSpotNotifications': friendAtSpotNotifications,
      'friendLiveShareNotifications': friendLiveShareNotifications,
      'publicProfile': publicProfile,
      'showGarage': showGarage,
    };
  }

  UserSettingsData copyWith({
    String? instagram,
    String? tiktok,
    String? telegram,
    bool? reviewNotifications,
    bool? likeNotifications,
    bool? commentNotifications,
    bool? newSpotNotifications,
    bool? newMessageNotifications,
    bool? xpNotifications,
    bool? friendAtSpotNotifications,
    bool? friendLiveShareNotifications,
    bool? publicProfile,
    bool? showGarage,
  }) {
    return UserSettingsData(
      instagram: instagram ?? this.instagram,
      tiktok: tiktok ?? this.tiktok,
      telegram: telegram ?? this.telegram,
      reviewNotifications: reviewNotifications ?? this.reviewNotifications,
      likeNotifications: likeNotifications ?? this.likeNotifications,
      commentNotifications: commentNotifications ?? this.commentNotifications,
      newSpotNotifications: newSpotNotifications ?? this.newSpotNotifications,
      newMessageNotifications:
          newMessageNotifications ?? this.newMessageNotifications,
      xpNotifications: xpNotifications ?? this.xpNotifications,
      friendAtSpotNotifications:
          friendAtSpotNotifications ?? this.friendAtSpotNotifications,
      friendLiveShareNotifications:
          friendLiveShareNotifications ?? this.friendLiveShareNotifications,
      publicProfile: publicProfile ?? this.publicProfile,
      showGarage: showGarage ?? this.showGarage,
    );
  }
}

UserSettingsData defaultUserSettings() {
  return const UserSettingsData(
    instagram: '',
    tiktok: '',
    telegram: '',
    reviewNotifications: true,
    likeNotifications: true,
    commentNotifications: true,
    newSpotNotifications: true,
    newMessageNotifications: true,
    xpNotifications: true,
    friendAtSpotNotifications: true,
    friendLiveShareNotifications: true,
    publicProfile: true,
    showGarage: true,
  );
}
