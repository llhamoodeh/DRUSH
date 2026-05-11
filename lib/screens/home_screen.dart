import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group_item.dart';
import '../models/schedule_item.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'groups_screen.dart';
import 'streak_screen.dart';
import 'vouchers_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthSession session;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.session, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFB71C1C);

  final BackendService _backendService = const BackendService();
  late Future<_DashboardData> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _loadData();
  }

  Future<_DashboardData> _loadData() async {
    final groups = await _backendService.fetchUserGroups(
      widget.session.token,
      userId: widget.session.user.id,
    );
    var schedules = await _backendService.fetchSchedules(
      widget.session.token,
    );
    // Show only personal schedules or those belonging to groups the user is a member of
    final userId = widget.session.user.id;
    final groupIds = groups.map((g) => g.id).toSet();
    schedules = schedules
        .where((s) => s.userId == userId || (s.groupId != 0 && groupIds.contains(s.groupId)))
        .toList();
    final coins = await _backendService.fetchUserCoins(
      widget.session.token,
    );
    schedules.sort(
      (left, right) => left.startDateTime.compareTo(right.startDateTime),
    );

    return _DashboardData(groups: groups, schedules: schedules, coins: coins);
  }

  void _reloadData() {
    setState(() {
      _futureData = _loadData();
    });
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/chat'),
        builder: (_) => ChatScreen(session: widget.session),
      ),
    );
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(session: widget.session),
      ),
    );

    if (mounted) {
      _reloadData();
    }
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupsScreen(session: widget.session),
      ),
    );

    if (mounted) {
      _reloadData();
    }
  }

  Future<void> _openStreak() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StreakScreen(session: widget.session),
      ),
    );

    if (mounted) {
      _reloadData();
    }
  }

  Future<void> _openVouchers(int coins) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VouchersScreen(
          session: widget.session,
          coins: coins,
        ),
      ),
    );

    if (mounted) {
      _reloadData();
    }
  }

  String _groupNameFor(_DashboardData data, int groupId) {
    if (groupId == 0) {
      return 'Personal';
    }

    for (final group in data.groups) {
      if (group.id == groupId) {
        return group.name;
      }
    }

    return 'Group #$groupId';
  }

  String _formatDate(DateTime dateTime) {
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

    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} · $hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<_DashboardData>(
          future: _futureData,
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
                        'Unable to load dashboard data.',
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
                      // Logo on white background
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF5F5F5)),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/logo.png',
                            width: 140,
                            height: 56,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _reloadData,
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
            final now = DateTime.now();
            final upcoming = data.schedules
                .where((item) => item.endDateTime.isAfter(now))
                .toList();
            final today = data.schedules
                .where((item) => item.occursOn(now))
                .toList();
            final nextThree = upcoming.take(3).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [redDark, red],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Image.asset(
                                              'assets/logo.png',
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.contain,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'DRUSH',
                                              style: GoogleFonts
                                                  .playfairDisplay(
                                                fontSize: 30,
                                                fontWeight: FontWeight.w700,
                                                color: redDark,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Welcome, ${widget.session.user.name}!',
                                        style: GoogleFonts.manrope(
                                          fontSize: 15,
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Material(
                                  color: Colors.white.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    onPressed: widget.onLogout,
                                    tooltip: 'Logout',
                                    icon: const Icon(
                                      Icons.logout_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final rowWidth = constraints.maxWidth < 780
                              ? constraints.maxWidth
                              : 780.0;
                          final cards = [
                            _MetricCard(
                              title: 'Coins',
                              value: data.coins.toString(),
                              subtitle: 'Your coin balance',
                              accentColor: const Color(0xFFFF9800),
                              iconPath: 'assets/coin.png',
                              centerValue: false,
                              valueAlignment: MainAxisAlignment.start,
                              actionLabel: 'Redeem',
                              onActionTap: () => _openVouchers(data.coins),
                            ),
                            _MetricCard(
                              title: 'Groups',
                              value: data.groups.length.toString(),
                              subtitle: 'List of your active groups',
                              accentColor: red,
                              actionLabel: 'Show all',
                              onActionTap: _openGroups,
                            ),
                            _MetricCard(
                              title: 'Upcoming',
                              value: upcoming.length.toString(),
                              subtitle: 'Schedule items still active',
                              accentColor: redDark,
                              actionLabel: 'View streak',
                              onActionTap: _openStreak,
                            ),
                            _MetricCard(
                              title: 'Today',
                              value: today.length.toString(),
                              subtitle: 'Tasks scheduled for now',
                              accentColor: const Color(0xFF7F1D1D),
                            ),
                          ];

                          const spacing = 16.0;
                          final columns = rowWidth >= 900
                              ? 4
                              : rowWidth >= 620
                                  ? 2
                                  : 1;
                          final totalSpacing = spacing * (columns - 1);
                          final cardWidth = (rowWidth - totalSpacing) / columns;

                          return Center(
                            child: SizedBox(
                              width: rowWidth,
                              child: Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: cards
                                    .map(
                                      (card) => SizedBox(
                                        width: cardWidth,
                                        child: card,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 860;
                          final calendarCard = _PanelCard(
                            title: 'Calendar preview',
                            child: _CalendarPreview(
                              month: DateTime(now.year, now.month, 1),
                              schedules: data.schedules,
                              onTap: _openCalendar,
                            ),
                          );

                          final eventsCard = _PanelCard(
                            title: 'Next events',
                            child: nextThree.isEmpty
                                ? const _EmptyState(
                                    title: 'No upcoming events yet',
                                    message:
                                        'Upcoming DRUSH schedules will appear here.',
                                  )
                                : Column(
                                    children: nextThree
                                        .map(
                                          (schedule) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _EventPreviewTile(
                                              groupName: _groupNameFor(
                                                data,
                                                schedule.groupId,
                                              ),
                                              timeLabel:
                                                  '${_formatDate(schedule.startDateTime)} - ${_formatDate(schedule.endDateTime)}',
                                              tips: schedule.tips,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: calendarCard),
                                const SizedBox(width: 16),
                                Expanded(child: eventsCard),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              calendarCard,
                              const SizedBox(height: 16),
                              eventsCard,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardData {
  final List<GroupItem> groups;
  final List<ScheduleItem> schedules;
  final int coins;

  const _DashboardData({required this.groups, required this.schedules, required this.coins});
}

class _PanelCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _PanelCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
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
            title,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB71C1C),
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _CalendarPreview extends StatelessWidget {
  final DateTime month;
  final List<ScheduleItem> schedules;
  final VoidCallback onTap;

  const _CalendarPreview({
    required this.month,
    required this.schedules,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const weekLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

    final monthLabel = '${months[month.month - 1]} ${month.year}';
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leadingEmpty = firstWeekday - 1;
    final totalCells = leadingEmpty + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = DateTime.now();

    final eventDays = <int>{};
    for (final schedule in schedules) {
      final start = schedule.startDateTime;
      if (start.year == month.year && start.month == month.month) {
        eventDays.add(start.day);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  monthLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB71C1C),
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap to open',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: weekLabels
                  .map(
                    (label) => Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Table(
              children: List.generate(rowCount, (rowIndex) {
                return TableRow(
                  children: List.generate(7, (colIndex) {
                    final cellIndex = rowIndex * 7 + colIndex;
                    final day = cellIndex - leadingEmpty + 1;
                    if (day < 1 || day > daysInMonth) {
                      return const SizedBox(height: 30);
                    }

                    final isToday = day == today.day &&
                        month.month == today.month &&
                        month.year == today.year;
                    final hasEvent = eventDays.contains(day);
                    final dayLabel = Text(
                      '$day',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? const Color(0xFFB71C1C)
                            : Colors.black87,
                      ),
                    );

                    return SizedBox(
                      height: 30,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: const Color(0xFFFFF5F5),
                                      borderRadius: BorderRadius.circular(10),
                                    )
                                  : null,
                              child: dayLabel,
                            ),
                            if (hasEvent) ...[
                              const SizedBox(height: 2),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFB71C1C),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventPreviewTile extends StatelessWidget {
  final String groupName;
  final String timeLabel;
  final String? tips;

  const _EventPreviewTile({
    required this.groupName,
    required this.timeLabel,
    required this.tips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupName,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: const Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeLabel,
            style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
          ),
          if ((tips ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tips!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 12, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final String? iconPath;
  final bool centerValue;
  final MainAxisAlignment valueAlignment;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    this.actionLabel,
    this.onActionTap,
    this.iconPath,
    this.centerValue = false,
    this.valueAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
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
          Row(
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE53935),
                ),
              ),
              const Spacer(),
              if (actionLabel != null && onActionTap != null)
                InkWell(
                  onTap: onActionTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      actionLabel!,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: centerValue
                      ? Alignment.center
                      : (valueAlignment == MainAxisAlignment.end
                          ? Alignment.centerRight
                          : Alignment.centerLeft),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        if (iconPath != null)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Image.asset(
                                iconPath!,
                                width: 30,
                                height: 30,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        TextSpan(
                          text: value,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
