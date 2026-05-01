import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group_item.dart';
import '../models/schedule_item.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import 'calendar_screen.dart';

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
    final groups = await _backendService.fetchGroups(widget.session.token);
    final schedules = await _backendService.fetchSchedules(
      widget.session.token,
    );
    schedules.sort(
      (left, right) => left.startDateTime.compareTo(right.startDateTime),
    );

    return _DashboardData(groups: groups, schedules: schedules);
  }

  void _reloadData() {
    setState(() {
      _futureData = _loadData();
    });
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

  String _groupNameFor(_DashboardData data, int groupId) {
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

  String _formatCreated(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Created time not set';
    }

    return 'Created ${_formatDate(dateTime)}';
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
            final nearestUpcoming = upcoming.isNotEmpty ? upcoming.first : null;

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
                                      Text(
                                        'DRUSH CONTROL',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Welcome, ${widget.session.user.name}. Manage live schedules through the DRUSH API.',
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
                                TextButton(
                                  onPressed: widget.onLogout,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.12,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Logout',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: _openCalendar,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: redDark,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Open Calendar',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton(
                                  onPressed: _reloadData,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    'Refresh',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 780;
                          final cards = [
                            _MetricCard(
                              title: 'Groups',
                              value: data.groups.length.toString(),
                              subtitle: 'Loaded from DRUSH API',
                              accentColor: red,
                            ),
                            _MetricCard(
                              title: 'Upcoming',
                              value: upcoming.length.toString(),
                              subtitle: 'Schedule items still active',
                              accentColor: redDark,
                            ),
                            _MetricCard(
                              title: 'Today',
                              value: today.length.toString(),
                              subtitle: 'Tasks scheduled for now',
                              accentColor: const Color(0xFF7F1D1D),
                            ),
                          ];

                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 16),
                                Expanded(child: cards[1]),
                                const SizedBox(width: 16),
                                Expanded(child: cards[2]),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              cards[0],
                              const SizedBox(height: 16),
                              cards[1],
                              const SizedBox(height: 16),
                              cards[2],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 860;
                          final left = _PanelCard(
                            title: 'Next task',
                            child: nearestUpcoming == null
                                ? _EmptyState(
                                    title: 'No scheduled tasks yet',
                                    message:
                                        'Open the calendar and create a schedule entry from live DRUSH data.',
                                    actionLabel: 'Open Calendar',
                                    onAction: _openCalendar,
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _groupNameFor(
                                          data,
                                          nearestUpcoming.groupId,
                                        ),
                                        style: GoogleFonts.manrope(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: redDark,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${_formatDate(nearestUpcoming.startDateTime)} to ${_formatDate(nearestUpcoming.endDateTime)}',
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatCreated(
                                          nearestUpcoming.createdAt,
                                        ),
                                        style: GoogleFonts.manrope(
                                          fontSize: 12,
                                          color: Colors.black45,
                                        ),
                                      ),
                                      if ((nearestUpcoming.tips ?? '')
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          nearestUpcoming.tips!,
                                          style: GoogleFonts.manrope(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          );

                          final right = _PanelCard(
                            title: 'Recent DRUSH schedules',
                            child: data.schedules.isEmpty
                                ? const _EmptyState(
                                    title: 'Nothing loaded yet',
                                    message:
                                        'The schedule table is currently empty.',
                                  )
                                : Column(
                                    children: data.schedules
                                        .take(5)
                                        .map(
                                          (schedule) => Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _ScheduleTile(
                                              groupName: _groupNameFor(
                                                data,
                                                schedule.groupId,
                                              ),
                                              subtitle:
                                                  '${_formatDate(schedule.startDateTime)} • ${_formatDate(schedule.endDateTime)}',
                                              createdLabel: _formatCreated(
                                                schedule.createdAt,
                                              ),
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
                                Expanded(child: left),
                                const SizedBox(width: 16),
                                Expanded(child: right),
                              ],
                            );
                          }

                          return Column(
                            children: [left, const SizedBox(height: 16), right],
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

  const _DashboardData({required this.groups, required this.schedules});
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

class _ScheduleTile extends StatelessWidget {
  final String groupName;
  final String subtitle;
  final String createdLabel;
  final String? tips;

  const _ScheduleTile({
    required this.groupName,
    required this.subtitle,
    required this.createdLabel,
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
            subtitle,
            style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            createdLabel,
            style: GoogleFonts.manrope(fontSize: 12, color: Colors.black45),
          ),
          if ((tips ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tips!,
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.black87),
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

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
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
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
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
