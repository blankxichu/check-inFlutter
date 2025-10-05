class ChatThread {
  final String id;
  final List<String> participants;
  final String? lastMessageText;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final Map<String, int> unread; // uid -> count
  ChatThread({
    required this.id,
    required this.participants,
    required this.lastMessageText,
    required this.lastMessageSenderId,
    required this.lastMessageAt,
    required this.unread,
  });
}
