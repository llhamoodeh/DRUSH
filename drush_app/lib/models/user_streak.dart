class UserStreak {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastStreakDate;
  final int totalOnTimeCompletions;
  final int totalLateCompletions;

  const UserStreak({
    required this.currentStreak,
    required this.longestStreak,
    this.lastStreakDate,
    required this.totalOnTimeCompletions,
    required this.totalLateCompletions,
  });

  factory UserStreak.fromJson(Map<String, dynamic> json) {
    return UserStreak(
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      lastStreakDate: json['lastStreakDate'] != null
          ? DateTime.tryParse(json['lastStreakDate'].toString())
          : null,
      totalOnTimeCompletions: (json['totalOnTimeCompletions'] as num?)?.toInt() ?? 0,
      totalLateCompletions: (json['totalLateCompletions'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isStreakActive {
    if (lastStreakDate == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastStreakDate!).inDays;
    // Streak is active if last completion was today or yesterday
    return difference <= 1;
  }
}
