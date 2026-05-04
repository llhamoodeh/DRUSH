class ChatMessage {
  final int id;
  final int userId;
  final String role;
  final String message;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.userId,
    required this.role,
    required this.message,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawUserId = json['userid'] ?? json['userId'];
    final rawCreatedAt = json['createdat'] ?? json['createdAt'];

    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    final userId = rawUserId is int
        ? rawUserId
        : int.tryParse('$rawUserId') ?? 0;

    final createdAt = DateTime.tryParse(rawCreatedAt?.toString() ?? '') ??
        DateTime.now();

    return ChatMessage(
      id: id,
      userId: userId,
      role: (json['role'] ?? 'assistant').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt: createdAt,
    );
  }
}
