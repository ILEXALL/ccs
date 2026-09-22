import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:ccs_app/core/firestore/collections.dart' show usersCollection;
import 'package:ccs_app/core/firestore/firestore_tracking.dart'
    show FirestoreDebugQueryExtension;
import 'package:ccs_app/core/localization/ccs_text.dart' show CcsText, trText;
import 'package:ccs_app/core/theme/app_theme.dart' show blue;
import 'package:ccs_app/features/friends/models/friend_user.dart'
    show FriendUserData;
import 'package:ccs_app/features/community/chats/models/mention_token.dart'
    show activeMention;
import 'package:ccs_app/features/friends/data/user_search.dart'
    show matchingFriendUsers, normalizeFriendSearch;

class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final int? minLines, maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final InputDecoration? decoration;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final List<String>? allowedUserIds;
  final Stream<List<FriendUserData>> Function()? loadUsers;
  final String? currentUid;
  const MentionTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.decoration,
    this.onSubmitted,
    this.autofocus = false,
    this.allowedUserIds,
    this.loadUsers,
    this.currentUid,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  late final FriendUserSearch search;
  late FocusNode focus;
  String query = '';
  @override
  void initState() {
    super.initState();
    focus = widget.focusNode ?? FocusNode();
    search = FriendUserSearch(
      currentUid:
          widget.currentUid ?? FirebaseAuth.instance.currentUser?.uid ?? '',
      loadUsers:
          widget.loadUsers ??
          () => usersCollection()
              .debugSnapshots('mentions: searchable user directory')
              .map(
                (snapshot) =>
                    snapshot.docs.map(FriendUserData.fromFirestore).toList(),
              ),
    );
    widget.controller.addListener(changed);
    focus.addListener(changed);
  }

  void changed() {
    final next = focus.hasFocus
        ? activeMention(widget.controller.value)?.group(1) ?? ''
        : '';
    if (next == query) return;
    query = next;
    search.search(next);
  }

  void selectUser(FriendUserData user) {
    final value = widget.controller.value;
    final match = activeMention(value);
    if (match == null) return;
    // Replace the entire token if the caret was moved into its middle.
    final suffix = RegExp(
      r'^[A-Za-z0-9_]*',
    ).firstMatch(value.text.substring(value.selection.end))!;
    var end = value.selection.end + suffix.end;
    if (end < value.text.length && value.text[end] == ' ') end++;
    final replacement = '@${user.username} ';
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(match.start, end, replacement),
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
    );
    focus.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    focus.removeListener(changed);
    if (widget.focusNode == null) focus.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedBuilder(
        animation: search,
        builder: (context, _) {
          if (query.length < 2) return const SizedBox.shrink();
          final users = search.results
              .where(
                (user) =>
                    widget.allowedUserIds == null ||
                    widget.allowedUserIds!.contains(user.uid),
              )
              .take(6)
              .toList();
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            width: double.maxFinite,
            height: search.loading || search.error != null || users.isEmpty
                ? 48
                : (users.length > 3 ? 180 : users.length * 60.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF20232B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            constraints: const BoxConstraints(maxHeight: 180),
            child: search.loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator(),
                  )
                : search.error != null
                ? TextButton(
                    onPressed: search.retry,
                    child: CcsText(trText('Retry')),
                  )
                : users.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CcsText(
                      trText('No users found'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: blue.withValues(alpha: 0.2),
                            child: ClipOval(
                              child: user.photoUrl?.isNotEmpty == true
                                  ? Image.network(
                                      user.photoUrl!,
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, error, stack) =>
                                          const Icon(
                                            Icons.person,
                                            color: Colors.white70,
                                          ),
                                    )
                                  : const Icon(
                                      Icons.person,
                                      color: Colors.white70,
                                    ),
                            ),
                          ),
                          title: CcsText(
                            '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: user.name.isEmpty
                              ? null
                              : CcsText(
                                  user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white54),
                                ),
                          onTap: () => selectUser(user),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
      TextField(
        controller: widget.controller,
        focusNode: focus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        style: widget.style,
        decoration: widget.decoration,
        onSubmitted: widget.onSubmitted,
        autofocus: widget.autofocus,
      ),
    ],
  );
}

class FriendUserSearch extends ChangeNotifier {
  final Stream<List<FriendUserData>> Function() loadUsers;
  final String currentUid;
  FriendUserSearch({required this.loadUsers, required this.currentUid});
  StreamSubscription<List<FriendUserData>>? _subscription;
  Timer? _debounce;
  List<FriendUserData>? _directory;
  String query = '';
  List<FriendUserData> results = const [];
  bool loading = false;
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  void search(String value) {
    query = normalizeFriendSearch(value);
    _debounce?.cancel();
    results = const [];
    error = null;
    loading = query.runes.length >= 2;
    notifyListeners();
    if (!loading) return;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_directory != null) _apply();
      if (_subscription == null) _listen();
    });
  }

  void _apply() {
    if (_disposed || query.runes.length < 2) return;
    results = matchingFriendUsers(_directory ?? [], query, currentUid);
    loading = false;
    error = null;
    notifyListeners();
  }

  void _listen() {
    final generation = ++_generation;
    _subscription = loadUsers().listen(
      (users) {
        if (_disposed || generation != _generation) return;
        _directory = users;
        if (!(_debounce?.isActive ?? false)) _apply();
      },
      onError: (Object failure) {
        if (_disposed || generation != _generation) return;
        loading = false;
        error = failure;
        notifyListeners();
      },
    );
  }

  void retry() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _directory = null;
    search(query);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
