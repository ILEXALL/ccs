String directChatIdFor(String firstUid, String secondUid) {
  final ids = [firstUid, secondUid]..sort();
  return 'direct_${ids[0]}_${ids[1]}';
}
