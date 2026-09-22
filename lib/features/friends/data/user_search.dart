import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;

String normalizeFriendSearch(String value) => value
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'^@+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<FriendUserData> matchingFriendUsers(
  Iterable<FriendUserData> users,
  String query,
  String currentUid,
) {
  final key = normalizeFriendSearch(query);
  if (key.runes.length < 2) return const [];
  int rank(FriendUserData user) {
    final username = normalizeFriendSearch(user.username);
    final name = normalizeFriendSearch(user.name);
    if (username == key) return 0;
    if (name == key) return 1;
    if (username.startsWith(key)) return 2;
    if (name.startsWith(key)) return 3;
    return 4;
  }

  final matches = users
      .where(
        (user) =>
            user.uid != currentUid &&
            user.canAppearInUserLists &&
            (normalizeFriendSearch(user.username).contains(key) ||
                normalizeFriendSearch(user.name).contains(key)),
      )
      .toList();
  matches.sort((a, b) {
    final relevance = rank(a).compareTo(rank(b));
    if (relevance != 0) return relevance;
    final username = a.username.toLowerCase().compareTo(
      b.username.toLowerCase(),
    );
    return username != 0 ? username : a.uid.compareTo(b.uid);
  });
  return matches;
}
