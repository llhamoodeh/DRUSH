class StreakLeaderboardEntry {
  final int rank;
  final int userId;
  final String name;
  final int coins;
  final int currentStreak;
  final int longestStreak;
  final int totalOnTimeCompletions;
  final int totalLateCompletions;
  final bool isCurrentUser;

  const StreakLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.name,
    required this.coins,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalOnTimeCompletions,
    required this.totalLateCompletions,
    required this.isCurrentUser,
  });

  factory StreakLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is int) {
        return value;
      }
      return int.tryParse('$value') ?? 0;
    }

    return StreakLeaderboardEntry(
      rank: parseInt(json['rank']),
      userId: parseInt(json['userId'] ?? json['userid']),
      name: (json['name'] ?? '').toString(),
      coins: parseInt(json['coins']),
      currentStreak: parseInt(json['currentStreak'] ?? json['currentstreak']),
      longestStreak: parseInt(json['longestStreak'] ?? json['longeststreak']),
      totalOnTimeCompletions: parseInt(
        json['totalOnTimeCompletions'] ?? json['totalontimecompletions'],
      ),
      totalLateCompletions: parseInt(
        json['totalLateCompletions'] ?? json['totallatecompletions'],
      ),
      isCurrentUser: json['isCurrentUser'] == true,
    );
  }
}
