import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/streak_leaderboard_entry.dart';
import '../models/user_streak.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';

class StreakScreen extends StatefulWidget {
  final AuthSession session;

  const StreakScreen({super.key, required this.session});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color orange = Color(0xFFFF9800);
  static const Color green = Color(0xFF4CAF50);

  final BackendService _backendService = const BackendService();
  late Future<_StreakData> _futureStreak;

  @override
  void initState() {
    super.initState();
    _futureStreak = _loadData();
  }

  void _reloadStreak() {
    setState(() {
      _futureStreak = _loadData();
    });
  }

  Future<_StreakData> _loadData() async {
    final results = await Future.wait([
      _backendService.fetchUserStreak(widget.session.token),
      _backendService.fetchStreakLeaderboard(widget.session.token),
    ]);

    final streak = results[0] as UserStreak;
    final leaderboard = results[1] as List<StreakLeaderboardEntry>;

    return _StreakData(streak: streak, leaderboard: leaderboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: redDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Your Streak',
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: redDark,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<_StreakData>(
        future: _futureStreak,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load streak data.',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: redDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _reloadStreak,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redDark,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final streak = data.streak;
          final leaderboard = data.leaderboard.take(10).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Current Streak Card
                    _StreakCard(
                      title: 'Current Streak',
                      value: streak.currentStreak.toString(),
                      subtitle: 'days',
                      accentColor: streak.isStreakActive ? orange : Colors.grey,
                      icon: Icons.local_fire_department_rounded,
                      isActive: streak.isStreakActive,
                    ),
                    const SizedBox(height: 20),

                    // Longest Streak Card
                    _StreakCard(
                      title: 'Longest Streak',
                      value: streak.longestStreak.toString(),
                      subtitle: 'days',
                      accentColor: const Color(0xFF9C27B0),
                      icon: Icons.emoji_events_rounded,
                    ),
                    const SizedBox(height: 28),

                    // Statistics Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFFFF5F5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Statistics',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: redDark,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _StatRow(
                            label: 'On-time Completions',
                            value: streak.totalOnTimeCompletions.toString(),
                            color: green,
                          ),
                          const SizedBox(height: 16),
                          _StatRow(
                            label: 'Late Completions',
                            value: streak.totalLateCompletions.toString(),
                            color: red,
                          ),
                          const SizedBox(height: 16),
                          _StatRow(
                            label: 'Completion Rate',
                            value:
                                '${_calculateCompletionRate(streak.totalOnTimeCompletions, streak.totalLateCompletions).toStringAsFixed(1)}%',
                            color: const Color(0xFF2196F3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Last Active Date
                    if (streak.lastStreakDate != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFE0E0)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Last Active',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDate(streak.lastStreakDate!),
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: redDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),

                    // Motivational Message
                    _MotivationalCard(
                      streak: streak,
                    ),
                    const SizedBox(height: 24),
                    _LeaderboardSection(entries: leaderboard),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _calculateCompletionRate(int onTime, int late) {
    final total = onTime + late;
    if (total == 0) return 0;
    return (onTime / total) * 100;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _StreakData {
  final UserStreak streak;
  final List<StreakLeaderboardEntry> leaderboard;

  const _StreakData({
    required this.streak,
    required this.leaderboard,
  });
}

class _StreakCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color accentColor;
  final IconData icon;
  final bool isActive;

  const _StreakCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    required this.icon,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentColor.withValues(alpha: 0.1), accentColor.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accentColor, size: 32),
              const SizedBox(width: 12),
              if (!isActive)
                Tooltip(
                  message: 'Keep completing tasks to maintain your streak!',
                  child: Icon(Icons.info_outline, color: Colors.grey[400], size: 20),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 56,
              fontWeight: FontWeight.w700,
              color: accentColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MotivationalCard extends StatelessWidget {
  final UserStreak streak;

  const _MotivationalCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    String message;
    Color bgColor;
    Color textColor;

    if (streak.currentStreak == 0) {
      message = 'Start a new streak by completing your next task on time!';
      bgColor = const Color(0xFFE3F2FD);
      textColor = const Color(0xFF1565C0);
    } else if (streak.currentStreak < 7) {
      message = 'Keep it up! You\'re building momentum!';
      bgColor = const Color(0xFFFFF3E0);
      textColor = const Color(0xFFE65100);
    } else if (streak.currentStreak < 30) {
      message = 'Impressive! You\'re on a fantastic streak!';
      bgColor = const Color(0xFFF3E5F5);
      textColor = const Color(0xFF6A1B9A);
    } else {
      message = 'Outstanding! You\'re a streak master!';
      bgColor = const Color(0xFFE8F5E9);
      textColor = const Color(0xFF1B5E20);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _LeaderboardSection extends StatelessWidget {
  final List<StreakLeaderboardEntry> entries;

  const _LeaderboardSection({required this.entries});

  Color _rankColor(int rank) {
    if (rank == 1) {
      return const Color(0xFFFFB300);
    }
    if (rank == 2) {
      return const Color(0xFF90A4AE);
    }
    if (rank == 3) {
      return const Color(0xFFB87333);
    }
    return const Color(0xFFB71C1C);
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFF0F0)),
        ),
        child: Text(
          'Leaderboard will appear once users complete tasks.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFF0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leaderboard',
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 14),
          ...entries.map((entry) {
            final accent = _rankColor(entry.rank);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: entry.isCurrentUser
                    ? const Color(0xFFFFF4F4)
                    : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: entry.isCurrentUser
                      ? const Color(0xFFFFD7D7)
                      : const Color(0xFFF0F0F0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${entry.rank}',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.isCurrentUser ? '${entry.name} (You)' : entry.name,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E1E1E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.coins} coins',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFEF6C00),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${entry.currentStreak}d',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB71C1C),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
