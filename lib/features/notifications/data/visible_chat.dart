// Resolve route visibility at delivery time, including stacked conversations.
final visibleChatRoutes = <Object, String? Function()>{};
bool chatIsVisible(String chatId) =>
    chatId.isNotEmpty &&
    visibleChatRoutes.values.any((read) => read() == chatId);
