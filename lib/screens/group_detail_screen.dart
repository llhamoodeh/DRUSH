import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/group_item.dart';
import '../models/group_leaderboard_entry.dart';
import '../models/group_member.dart';
import '../models/group_task.dart';
import '../models/schedule_item.dart';
import 'calendar_screen.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';

class GroupDetailScreen extends StatefulWidget {
  final AuthSession session;
  final GroupItem group;

  const GroupDetailScreen({
    super.key,
    required this.session,
    required this.group,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  static const Color redDark = Color(0xFFB71C1C);
  static const Color redSoft = Color(0xFFFFF5F5);

  final BackendService _backendService = const BackendService();
  final TextEditingController _emailController = TextEditingController();
  final AudioPlayer _coinPlayer = AudioPlayer();

  bool _loading = true;
  bool _updating = false;
  String? _error;
  List<GroupMember> _members = const [];
  List<GroupTask> _tasks = const [];
  List<GroupLeaderboardEntry> _leaderboard = const [];
  bool _membersUnavailable = false;
  bool _tasksUnavailable = false;
  bool _leaderboardUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _coinPlayer.dispose();
    super.dispose();
  }

  bool get _isCreator => widget.group.creatorId == widget.session.user.id;

  bool get _hasUnavailableEndpoints =>
      _membersUnavailable || _tasksUnavailable || _leaderboardUnavailable;

  bool _isNotFound(Object err) => err is ApiException && err.statusCode == 404;

  String _memberNameFor(int? userId) {
    if (userId == null) {
      return 'Unknown';
    }

    if (userId == widget.session.user.id) {
      return 'You';
    }

    for (final member in _members) {
      if (member.id == userId) {
        return member.name;
      }
    }

    if (userId == widget.group.creatorId) {
      return 'Creator';
    }

    return 'User #$userId';
  }

  String _taskDescriptionFor(ScheduleItem schedule) {
    final description = (schedule.tips ?? '').trim();
    return description.isEmpty ? 'No description' : description;
  }

  Future<void> _openGroupCalendar({ScheduleItem? schedule}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(
          session: widget.session,
          initialGroupId: schedule?.groupId ?? widget.group.id,
          initialSchedule: schedule,
          openEditorOnLoad: true,
        ),
      ),
    );

    if (mounted) {
      await _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _membersUnavailable = false;
      _tasksUnavailable = false;
      _leaderboardUnavailable = false;
    });

    try {
      bool membersUnavailable = false;
      bool tasksUnavailable = false;
      bool leaderboardUnavailable = false;

      List<GroupMember> members = const [];
      List<GroupTask> tasks = const [];
      List<GroupLeaderboardEntry> leaderboard = const [];

      try {
        members = await _backendService.fetchGroupMembers(
          token: widget.session.token,
          groupId: widget.group.id,
        );
      } catch (err) {
        if (_isNotFound(err)) {
          membersUnavailable = true;
        } else {
          rethrow;
        }
      }

      try {
        tasks = await _backendService.fetchGroupTasks(
          token: widget.session.token,
          groupId: widget.group.id,
        );
      } catch (err) {
        if (_isNotFound(err)) {
          tasksUnavailable = true;
        } else {
          rethrow;
        }
      }

      try {
        leaderboard = await _backendService.fetchGroupLeaderboard(
          token: widget.session.token,
          groupId: widget.group.id,
        );
      } catch (err) {
        if (_isNotFound(err)) {
          leaderboardUnavailable = true;
        } else {
          rethrow;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _members = members;
        _tasks = tasks;
        _leaderboard = leaderboard;
        _membersUnavailable = membersUnavailable;
        _tasksUnavailable = tasksUnavailable;
        _leaderboardUnavailable = leaderboardUnavailable;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addMember() async {
    if (!_isCreator || _updating) {
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return;
    }

    setState(() {
      _updating = true;
      _error = null;
    });

    try {
      await _backendService.addGroupMember(
        token: widget.session.token,
        groupId: widget.group.id,
        email: email,
      );

      if (!mounted) {
        return;
      }

      _emailController.clear();
      await _loadData();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _updating = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    if (!_isCreator || _updating) {
      return;
    }

    setState(() {
      _updating = true;
      _error = null;
    });

    try {
      await _backendService.removeGroupMember(
        token: widget.session.token,
        groupId: widget.group.id,
        userId: member.id,
      );

      if (!mounted) {
        return;
      }

      await _loadData();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _updating = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
  }

  Future<void> _completeTask(GroupTask task) async {
    if (_updating || task.isCompleted) {
      return;
    }

    final isOwner = task.schedule.userId == widget.session.user.id;
    if (!isOwner) {
      return;
    }

    setState(() {
      _updating = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      if (!now.isBefore(task.schedule.endDateTime)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot complete task after the deadline.')),
        );
        setState(() {
          _updating = false;
        });
        return;
      }

      await _backendService.completeGroupTask(
        token: widget.session.token,
        groupId: widget.group.id,
        scheduleId: task.schedule.id,
      );

      try {
        await _coinPlayer.play(AssetSource('coin.mp4'));
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Congrats! 🎉🎊 Task completed before the deadline.')),
      );

      if (!mounted) {
        return;
      }

      await _loadData();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
        _updating = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
        });
      }
    }
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

  String _missingLabel() {
    final missing = <String>[];
    if (_membersUnavailable) {
      missing.add('members');
    }
    if (_tasksUnavailable) {
      missing.add('tasks');
    }
    if (_leaderboardUnavailable) {
      missing.add('leaderboard');
    }

    if (missing.isEmpty) {
      return 'Group data is unavailable.';
    }

    final list = missing.join(', ');
    return 'Missing API endpoints for $list.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.group.name,
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            color: redDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
            color: redDark,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: GoogleFonts.manrope(
                            color: redDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_hasUnavailableEndpoints)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _InfoBanner(
                          title: 'Group endpoints unavailable',
                          message:
                              '${_missingLabel()} Update the API host or restart the latest server.',
                        ),
                      ),
                    _GroupSummaryCard(
                      group: widget.group,
                      isCreator: _isCreator,
                      creatorName: _memberNameFor(widget.group.creatorId),
                      members: _members.length,
                      tasks: _tasks.length,
                      completedTasks: _tasks
                          .where((task) => task.isCompleted)
                          .length,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _updating
                            ? null
                            : () => _openGroupCalendar(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: redDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(
                          'Create task',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Leaderboard',
                      child: _leaderboardUnavailable
                          ? const _EmptyState(
                              title: 'Leaderboard unavailable',
                              message:
                                  'The API host does not provide group leaderboard data yet.',
                            )
                          : _leaderboard.isEmpty
                          ? _EmptyState(
                              title: 'No completions yet',
                              message: 'Complete a task to see rankings.',
                            )
                          : Column(
                              children: _leaderboard
                                  .map(
                                    (entry) => _LeaderboardTile(entry: entry),
                                  )
                                  .toList(),
                            ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Members',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isCreator && !_membersUnavailable) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: redSoft,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: redDark.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.person_add_rounded,
                                        color: redDark,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Invite members',
                                        style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: redDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Add teammates by email to collaborate on tasks.',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _addMember(),
                                    decoration: InputDecoration(
                                      hintText: 'email@example.com',
                                      prefixIcon: const Icon(
                                        Icons.alternate_email_rounded,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _updating ? null : _addMember,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: redDark,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: _updating
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            )
                                          : Text(
                                              'Add member',
                                              style: GoogleFonts.manrope(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_membersUnavailable)
                            const _EmptyState(
                              title: 'Members unavailable',
                              message:
                                  'The API host does not expose member lists yet.',
                            )
                          else if (_members.isEmpty)
                            _EmptyState(
                              title: 'No members yet',
                              message: 'Invite teammates to join this group.',
                            )
                          else
                            Column(
                              children: _members
                                  .map(
                                    (member) => _MemberTile(
                                      member: member,
                                      canRemove:
                                          _isCreator &&
                                          member.id != widget.group.creatorId,
                                      onRemove: () => _removeMember(member),
                                    ),
                                  )
                                  .toList(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Tasks',
                      child: _tasksUnavailable
                          ? const _EmptyState(
                              title: 'Tasks unavailable',
                              message:
                                  'The API host does not expose group tasks yet.',
                            )
                          : _tasks.isEmpty
                          ? _EmptyState(
                              title: 'No tasks yet',
                              message:
                                  'Schedule tasks in the calendar to see them here.',
                            )
                          : Column(
                              children: _tasks
                                  .map(
                                    (task) => _TaskTile(
                                      title: _taskDescriptionFor(task.schedule),
                                      addedBy: _memberNameFor(
                                        task.schedule.createdBy,
                                      ),
                                      timeLabel:
                                          '${_formatDate(task.schedule.startDateTime)} - ${_formatDate(task.schedule.endDateTime)}',
                                      tips: task.schedule.tips,
                                      isOwner:
                                          task.schedule.userId ==
                                          widget.session.user.id,
                                      isCompleted: task.isCompleted,
                                      onTap: () => _openGroupCalendar(
                                        schedule: task.schedule,
                                      ),
                                      onComplete: () => _completeTask(task),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String title;
  final String message;

  const _InfoBanner({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    const redDark = Color(0xFFB71C1C);
    const redSoft = Color(0xFFFFF5F5);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: redSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: redDark.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, color: redDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: redDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupSummaryCard extends StatelessWidget {
  final GroupItem group;
  final bool isCreator;
  final String creatorName;
  final int members;
  final int tasks;
  final int completedTasks;

  const _GroupSummaryCard({
    required this.group,
    required this.isCreator,
    required this.creatorName,
    required this.members,
    required this.tasks,
    required this.completedTasks,
  });

  @override
  Widget build(BuildContext context) {
    const redDark = Color(0xFFB71C1C);
    const redSoft = Color(0xFFFFF5F5);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: redSoft),
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
              Expanded(
                child: Text(
                  group.name,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: redDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: redSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isCreator ? 'Creator' : 'Member',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: redDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCreator ? 'You created this group.' : 'Created by $creatorName.',
            style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryChip(label: 'Members', value: members.toString()),
              _SummaryChip(label: 'Tasks', value: tasks.toString()),
              _SummaryChip(
                label: 'Completed',
                value: completedTasks.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    const redDark = Color(0xFFB71C1C);
    const redSoft = Color(0xFFFFF5F5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: redSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w700,
              color: redDark,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMember member;
  final bool canRemove;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  member.email,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          if (canRemove)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              color: const Color(0xFFB71C1C),
              tooltip: 'Remove',
            ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final String title;
  final String addedBy;
  final String timeLabel;
  final String? tips;
  final bool isOwner;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  const _TaskTile({
    required this.title,
    required this.addedBy,
    required this.timeLabel,
    required this.tips,
    required this.isOwner,
    required this.isCompleted,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFF5F5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFB71C1C),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Added by $addedBy',
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Text(
                timeLabel,
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
              ),
              if ((tips ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tips!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isCompleted ? 'Completed' : 'Pending',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isCompleted
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isOwner && !isCompleted)
                    TextButton(
                      onPressed: onComplete,
                      child: const Text('Mark completed'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final GroupLeaderboardEntry entry;

  const _LeaderboardTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.email,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.completedCount.toString(),
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB71C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
