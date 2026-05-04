class GroupLeaderboardEntry {
  final int id;
  final String name;
  final String email;
  final int completedCount;

  const GroupLeaderboardEntry({
    required this.id,
    required this.name,
    required this.email,
    required this.completedCount,
  });

  factory GroupLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawCompleted = json['completedCount'] ?? json['completedcount'];

    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
    final completedCount = rawCompleted is int
        ? rawCompleted
        : int.tryParse('$rawCompleted') ?? 0;

    return GroupLeaderboardEntry(
      id: id,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      completedCount: completedCount,
    );
  }
}
