import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/group_item.dart';
import '../models/schedule_item.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';

class CalendarScreen extends StatefulWidget {
  final AuthSession session;
  final int? initialGroupId;
  final ScheduleItem? initialSchedule;
  final bool openEditorOnLoad;

  const CalendarScreen({
    super.key,
    required this.session,
    this.initialGroupId,
    this.initialSchedule,
    this.openEditorOnLoad = false,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color redSoft = Color(0xFFFFF5F5);

  final BackendService _backendService = const BackendService();
  final TextEditingController _tipsController = TextEditingController();
  final AudioPlayer _coinPlayer = AudioPlayer();

  bool _loading = true;
  bool _saving = false;
  bool _completingTask = false;
  String? _error;
  String? _statusMessage;

  List<GroupItem> _groups = <GroupItem>[];
  List<ScheduleItem> _schedules = <ScheduleItem>[];

  late DateTime _selectedMonth;
  late DateTime _selectedDate;
  int _selectedGroupId = 0;
  DateTime? _startDateTime;
  DateTime? _endDateTime;
  DateTime? _createdAt;
  ScheduleItem? _editingSchedule;
  bool _autoEditorScheduled = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initialSchedule = widget.initialSchedule;
    final baseDate = initialSchedule?.startDateTime ?? now;
    _selectedMonth = DateTime(baseDate.year, baseDate.month, 1);
    _selectedDate = DateTime(baseDate.year, baseDate.month, baseDate.day);
    _selectedGroupId = initialSchedule?.groupId ?? widget.initialGroupId ?? 0;
    _startDateTime =
        initialSchedule?.startDateTime ??
        DateTime(now.year, now.month, now.day, 9, 0);
    _endDateTime =
        initialSchedule?.endDateTime ??
        DateTime(now.year, now.month, now.day, 10, 0);
    _createdAt = initialSchedule?.createdAt ?? now;
    _loadData();
  }

  @override
  void dispose() {
    _tipsController.dispose();
    _coinPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await _backendService.fetchGroups(widget.session.token);
      var schedules = await _backendService.fetchSchedules(
        widget.session.token,
      );
      // Filter schedules to only the user's personal items or groups they're a member of
      final userId = widget.session.user.id;
      final groupIds = groups.map((g) => g.id).toSet();
      schedules = schedules
          .where((s) => s.userId == userId || (s.groupId != 0 && groupIds.contains(s.groupId)))
          .toList();
      schedules.sort(
        (left, right) => left.startDateTime.compareTo(right.startDateTime),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _groups = groups;
        _schedules = schedules;
        if (_selectedGroupId != 0 &&
            !groups.any((group) => group.id == _selectedGroupId)) {
          _selectedGroupId = 0;
        }
        _startDateTime ??= _defaultStartFor(_selectedDate);
        _endDateTime ??= _defaultEndFor(_selectedDate);
        _loading = false;
      });

      if (widget.openEditorOnLoad && !_autoEditorScheduled) {
        _autoEditorScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }

          if (widget.initialSchedule != null) {
            _beginEdit(widget.initialSchedule!);
          } else {
            _resetForm(date: _selectedDate, groupId: widget.initialGroupId);
          }

          _showScheduleFormSheet();
        });
      }
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

  void _resetForm({DateTime? date, int? groupId}) {
    final targetDate = date ?? _selectedDate;

    setState(() {
      _editingSchedule = null;
      _selectedDate = targetDate;
      _selectedMonth = DateTime(targetDate.year, targetDate.month, 1);
      _selectedGroupId = groupId ?? 0;
      _startDateTime = _defaultStartFor(targetDate);
      _endDateTime = _defaultEndFor(targetDate);
      _createdAt = DateTime.now();
      _tipsController.clear();
    });
  }

  void _beginEdit(ScheduleItem schedule) {
    setState(() {
      _editingSchedule = schedule;
      _selectedDate = schedule.startDateTime;
      _selectedMonth = DateTime(
        schedule.startDateTime.year,
        schedule.startDateTime.month,
        1,
      );
      _selectedGroupId = _groups.any((group) => group.id == schedule.groupId)
          ? schedule.groupId
          : 0;
      _startDateTime = schedule.startDateTime;
      _endDateTime = schedule.endDateTime;
      _createdAt = schedule.createdAt ?? DateTime.now();
      _tipsController.text = schedule.tips ?? '';
      _statusMessage = null;
    });
  }

  Widget _buildFormContent(BuildContext sheetContext, {bool inSheet = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 640;
        final fieldWidth = useTwoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        Widget responsiveField(Widget child) {
          return SizedBox(width: fieldWidth, child: child);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editingSchedule != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: redSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Icon(Icons.edit_rounded, color: redDark),
                    Text(
                      'Editing an existing schedule.',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: redDark,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _resetForm(
                        date: _selectedDate,
                        groupId: _selectedGroupId,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            DropdownButtonFormField<int>(
              initialValue: _selectedGroupId,
              isExpanded: true,
              items: [
                const DropdownMenuItem<int>(value: 0, child: Text('No group')),
                ..._groups.map(
                  (group) => DropdownMenuItem<int>(
                    value: group.id,
                    child: Text(group.name, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              decoration: InputDecoration(
                labelText: 'Group (optional)',
                prefixIcon: const Icon(Icons.group_rounded),
                filled: true,
                fillColor: redSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _selectedGroupId = value ?? 0;
                });
              },
            ),
            const SizedBox(height: 14),
            if (useTwoColumns)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  responsiveField(
                    _buildDateField(
                      label: 'Start date',
                      value: _startDateTime ?? _defaultStartFor(_selectedDate),
                      onTap: _pickStartDate,
                      icon: Icons.calendar_month_rounded,
                    ),
                  ),
                  responsiveField(
                    _buildTimeField(
                      label: 'Start time',
                      value: _startDateTime ?? _defaultStartFor(_selectedDate),
                      onTap: _pickStartTime,
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                  responsiveField(
                    _buildDateField(
                      label: 'Deadline date',
                      value: _endDateTime ?? _defaultEndFor(_selectedDate),
                      onTap: _pickEndDate,
                      icon: Icons.event_available_rounded,
                    ),
                  ),
                  responsiveField(
                    _buildTimeField(
                      label: 'Deadline time',
                      value: _endDateTime ?? _defaultEndFor(_selectedDate),
                      onTap: _pickEndTime,
                      icon: Icons.alarm_rounded,
                    ),
                  ),
                  // Created date/time are auto-set and not editable in the form.
                ],
              )
            else ...[
              _buildDateField(
                label: 'Start date',
                value: _startDateTime ?? _defaultStartFor(_selectedDate),
                onTap: _pickStartDate,
                icon: Icons.calendar_month_rounded,
              ),
              const SizedBox(height: 12),
              _buildTimeField(
                label: 'Start time',
                value: _startDateTime ?? _defaultStartFor(_selectedDate),
                onTap: _pickStartTime,
                icon: Icons.schedule_rounded,
              ),
              const SizedBox(height: 12),
              _buildDateField(
                label: 'Deadline date',
                value: _endDateTime ?? _defaultEndFor(_selectedDate),
                onTap: _pickEndDate,
                icon: Icons.event_available_rounded,
              ),
              const SizedBox(height: 12),
              _buildTimeField(
                label: 'Deadline time',
                value: _endDateTime ?? _defaultEndFor(_selectedDate),
                onTap: _pickEndTime,
                icon: Icons.alarm_rounded,
              ),
              const SizedBox(height: 12),
              // Created date/time are auto-set and not editable in the form.
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _tipsController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Task details',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                filled: true,
                fillColor: redSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: GoogleFonts.manrope(
                  color: redDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (inSheet) {
                          final navigator = Navigator.of(sheetContext);
                          await _submitSchedule();
                          if (mounted && navigator.canPop()) {
                            navigator.pop();
                          }
                        } else {
                          await _submitSchedule();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: redDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        _editingSchedule == null
                            ? 'Save schedule'
                            : 'Update schedule',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showScheduleFormSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: _buildFormContent(sheetContext, inSheet: true),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(ScheduleItem schedule) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete schedule?'),
              content: Text(
                'Remove the schedule for ${_groupNameFor(schedule.groupId)} on ${_dateLabel(schedule.startDateTime)}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  DateTime _defaultStartFor(DateTime date) {
    return DateTime(date.year, date.month, date.day, 9, 0);
  }

  DateTime _defaultEndFor(DateTime date) {
    return DateTime(date.year, date.month, date.day, 10, 0);
  }

  DateTime _replaceDate(DateTime source, DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      source.hour,
      source.minute,
    );
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _monthYearLabel(DateTime dateTime) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.year}';
  }

  String _timeLabel(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _dateLabel(DateTime dateTime) {
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
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  String _createdLabel(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Created time not set';
    }

    return 'Created ${_dateLabel(createdAt)} at ${_timeLabel(createdAt)}';
  }

  Map<String, int> _scheduleCountsForMonth() {
    final counts = <String, int>{};
    for (final schedule in _schedules) {
      if (schedule.startDateTime.year != _selectedMonth.year ||
          schedule.startDateTime.month != _selectedMonth.month) {
        continue;
      }
      final key =
          '${schedule.startDateTime.year}-${schedule.startDateTime.month}-${schedule.startDateTime.day}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<DateTime?> _monthCells(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingBlankCells = firstDay.weekday % 7;
    final cells = <DateTime?>[];

    for (var i = 0; i < leadingBlankCells; i++) {
      cells.add(null);
    }

    for (var day = 1; day <= daysInMonth; day++) {
      cells.add(DateTime(month.year, month.month, day));
    }

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return cells;
  }

  List<ScheduleItem> _schedulesForDate(DateTime dateTime) {
    final matches = _schedules
        .where((item) => item.occursOn(dateTime))
        .toList();
    matches.sort(
      (left, right) => left.startDateTime.compareTo(right.startDateTime),
    );
    return matches;
  }

  String _groupNameFor(int groupId) {
    if (groupId == 0) {
      return 'Personal';
    }

    for (final group in _groups) {
      if (group.id == groupId) {
        return group.name;
      }
    }
    return 'Group #$groupId';
  }

  Future<void> _pickMonth(int monthOffset) async {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + monthOffset,
        1,
      );
      if (_selectedDate.year != _selectedMonth.year ||
          _selectedDate.month != _selectedMonth.month) {
        _selectedDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        _startDateTime = _defaultStartFor(_selectedDate);
        _endDateTime = _defaultEndFor(_selectedDate);
      }
    });
  }

  Future<void> _pickSelectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDate = picked;
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _startDateTime = _replaceDate(
        _startDateTime ?? _defaultStartFor(picked),
        picked,
      );
      _endDateTime = _replaceDate(
        _endDateTime ?? _defaultEndFor(picked),
        picked,
      );
    });
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDateTime ?? _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _startDateTime = _replaceDate(
        _startDateTime ?? _defaultStartFor(picked),
        picked,
      );
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDateTime ?? _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _endDateTime = _replaceDate(
        _endDateTime ?? _defaultEndFor(picked),
        picked,
      );
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _startDateTime ?? _defaultStartFor(_selectedDate),
      ),
    );

    if (picked == null) return;

    final base = _startDateTime ?? _defaultStartFor(_selectedDate);
    setState(() {
      _startDateTime = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _endDateTime ?? _defaultEndFor(_selectedDate),
      ),
    );

    if (picked == null) return;

    final base = _endDateTime ?? _defaultEndFor(_selectedDate);
    setState(() {
      _endDateTime = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickCreatedDate() async {
    final base = _createdAt ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _createdAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        base.hour,
        base.minute,
      );
    });
  }

  Future<void> _pickCreatedTime() async {
    final base = _createdAt ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );

    if (picked == null) return;

    setState(() {
      _createdAt = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _submitSchedule() async {
    debugPrint('[Schedule] save button pressed');

    if (_startDateTime == null || _endDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select start and end times first.')),
      );
      return;
    }

    if (!_endDateTime!.isAfter(_startDateTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
    });

    final wasEditing = _editingSchedule != null;
    final selectedGroupId = _selectedGroupId;
    final backendGroupId = selectedGroupId == 0 ? null : selectedGroupId;
    final createdAt = _createdAt ?? DateTime.now();

    try {
      final tips = _tipsController.text.trim().isEmpty
          ? null
          : _tipsController.text.trim();
      late ScheduleItem savedSchedule;
      debugPrint(
        '[Schedule] save ${wasEditing ? 'update' : 'create'} request: '
        'userId=${widget.session.user.id}, groupId=${backendGroupId ?? 'none'}, '
        'start=${_startDateTime!.toIso8601String()}, '
        'end=${_endDateTime!.toIso8601String()}, '
        'createdAt=${createdAt.toIso8601String()}, '
        'createdBy=${widget.session.user.id}, tips=${tips ?? ''}',
      );

      if (_editingSchedule == null) {
        savedSchedule = await _backendService.createSchedule(
          token: widget.session.token,
          userId: widget.session.user.id,
          groupId: backendGroupId,
          startDateTime: _startDateTime!,
          endDateTime: _endDateTime!,
          createdAt: createdAt,
          createdBy: widget.session.user.id,
          tips: tips,
        );
      } else {
        savedSchedule = await _backendService.updateSchedule(
          token: widget.session.token,
          original: _editingSchedule!,
          userId: widget.session.user.id,
          groupId: backendGroupId,
          startDateTime: _startDateTime!,
          endDateTime: _endDateTime!,
          createdAt: createdAt,
          createdBy: widget.session.user.id,
          tips: tips,
        );
      }

      await _loadData();
      _resetForm(date: _selectedDate, groupId: selectedGroupId);

      debugPrint(
        '[Schedule] save response: userId=${savedSchedule.userId}, '
        'groupId=${savedSchedule.groupId}, '
        'start=${savedSchedule.startDateTime.toIso8601String()}, '
        'end=${savedSchedule.endDateTime.toIso8601String()}, '
        'createdAt=${savedSchedule.createdAt?.toIso8601String() ?? ''}, '
        'createdBy=${savedSchedule.createdBy ?? ''}, '
        'tips=${savedSchedule.tips ?? ''}',
      );

      if (!mounted) return;

      setState(() {
        _statusMessage =
            'Schedule ${wasEditing ? 'updated' : 'created'}: ${_groupNameFor(savedSchedule.groupId)} on ${_dateLabel(savedSchedule.startDateTime)} at ${_timeLabel(savedSchedule.startDateTime)}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEditing
                ? 'Schedule updated successfully.'
                : 'Schedule saved successfully.',
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;

      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteSchedule(ScheduleItem schedule) async {
    final confirm = await _confirmDelete(schedule);
    if (!confirm) return;

    setState(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      await _backendService.deleteSchedule(
        token: widget.session.token,
        scheduleId: schedule.id,
      );

      if (_editingSchedule != null &&
          _editingSchedule!.id == schedule.id) {
        _resetForm(date: _selectedDate, groupId: _selectedGroupId);
      }

      await _loadData();

      if (!mounted) return;

      setState(() {
        _statusMessage =
            'Schedule deleted: ${_groupNameFor(schedule.groupId)} on ${_dateLabel(schedule.startDateTime)}';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Schedule deleted.')));
    } catch (err) {
      if (!mounted) return;

      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _completeSchedule(ScheduleItem schedule) async {
    if (_completingTask || schedule.isCompleted) {
      return;
    }

    if (schedule.userId != widget.session.user.id) {
      return;
    }

    setState(() {
      _completingTask = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final now = DateTime.now();
      if (!now.isBefore(schedule.endDateTime)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot complete task after the deadline.'),
          ),
        );
        return;
      }

      if (schedule.groupId == 0) {
        await _backendService.completeScheduleTask(
          token: widget.session.token,
          scheduleId: schedule.id,
        );
      } else {
        await _backendService.completeGroupTask(
          token: widget.session.token,
          groupId: schedule.groupId,
          scheduleId: schedule.id,
        );
      }

      try {
        await _coinPlayer.play(AssetSource('coin.mp4'));
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Congrats! 🎉🎊 Task completed before the deadline.'),
        ),
      );

      await _loadData();
    } catch (err) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _completingTask = false;
        });
      }
    }
  }

  Widget _buildDateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: redSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          _dateLabel(value),
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: redSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          _timeLabel(value),
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _groups.isEmpty && _schedules.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Calendar could not load.',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: redDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: redDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final monthCells = _monthCells(_selectedMonth);
    final counts = _scheduleCountsForMonth();
    final selectedDaySchedules = _schedulesForDate(_selectedDate);
    final showFab = MediaQuery.of(context).size.width <= 920;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _resetForm(date: _selectedDate, groupId: _selectedGroupId);
          _showScheduleFormSheet();
        },
        tooltip: 'Create schedule',
        backgroundColor: const Color(0xFFB71C1C),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: redDark,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Calendar',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: redDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: redSoft,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: red.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: redDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 920;

                      final calendarPanel = _PanelCard(
                        title: 'Monthly calendar',
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 420;
                            final gridSpacing = isCompact ? 6.0 : 10.0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _pickMonth(-1),
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                      ),
                                      color: redDark,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          _monthYearLabel(_selectedMonth),
                                          style: GoogleFonts.manrope(
                                            fontSize: isCompact ? 16 : 18,
                                            fontWeight: FontWeight.w800,
                                            color: redDark,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _pickMonth(1),
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                      ),
                                      color: redDark,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: List.generate(7, (index) {
                                    return Expanded(
                                      child: Center(
                                        child: Text(
                                          [
                                            'S',
                                            'M',
                                            'T',
                                            'W',
                                            'T',
                                            'F',
                                            'S',
                                          ][index],
                                          style: GoogleFonts.manrope(
                                            fontSize: isCompact ? 10 : 12,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 10),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: monthCells.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7,
                                        mainAxisSpacing: gridSpacing,
                                        crossAxisSpacing: gridSpacing,
                                        childAspectRatio: isCompact
                                            ? 0.92
                                            : 1.0,
                                      ),
                                  itemBuilder: (context, index) {
                                    final day = monthCells[index];
                                    if (day == null) {
                                      return const SizedBox.shrink();
                                    }

                                    final isSelected = _isSameDate(
                                      day,
                                      _selectedDate,
                                    );
                                    final count =
                                        counts['${day.year}-${day.month}-${day.day}'] ??
                                        0;

                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedDate = day;
                                          _startDateTime = _replaceDate(
                                            _startDateTime ??
                                                _defaultStartFor(day),
                                            day,
                                          );
                                          _endDateTime = _replaceDate(
                                            _endDateTime ?? _defaultEndFor(day),
                                            day,
                                          );
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isSelected ? redDark : redSoft,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? redDark
                                                : redSoft,
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: Stack(
                                          children: [
                                            Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                '${day.day}',
                                                style: GoogleFonts.manrope(
                                                  fontSize: isCompact ? 11 : 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : redDark,
                                                ),
                                              ),
                                            ),
                                            if (count > 0)
                                              Align(
                                                alignment:
                                                    Alignment.bottomRight,
                                                child: Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: red,
                                                        shape: BoxShape.circle,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      );

                      final selectedPanel = _PanelCard(
                        title: 'Selected day',
                        child: selectedDaySchedules.isEmpty
                            ? _EmptyState(
                                title:
                                    'No tasks on ${_dateLabel(_selectedDate)}',
                                message:
                                    'Choose another day or create a new schedule below.',
                                actionLabel: 'Pick day',
                                onAction: _pickSelectedDate,
                              )
                            : Column(
                                children: selectedDaySchedules
                                    .map(
                                      (schedule) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _ScheduleTile(
                                          groupName: _groupNameFor(
                                            schedule.groupId,
                                          ),
                                          subtitle:
                                              '${_dateLabel(schedule.startDateTime)} • ${_timeLabel(schedule.startDateTime)} - ${_timeLabel(schedule.endDateTime)}',
                                          createdLabel: _createdLabel(
                                            schedule.createdAt,
                                          ),
                                          tips: schedule.tips,
                                          completedAt: schedule.completedAt,
                                          canComplete:
                                              schedule.userId ==
                                                  widget.session.user.id &&
                                              !schedule.isCompleted &&
                                              DateTime.now().isBefore(
                                                schedule.endDateTime,
                                              ),
                                          onComplete: () =>
                                              _completeSchedule(schedule),
                                          onEdit: () {
                                            _beginEdit(schedule);
                                            if (showFab) {
                                              _showScheduleFormSheet();
                                            }
                                          },
                                          onDelete: () =>
                                              _deleteSchedule(schedule),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      );

                      final formWidget = _PanelCard(
                        title: _editingSchedule == null
                            ? 'Create schedule'
                            : 'Update schedule',
                        child: _buildFormContent(context),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  calendarPanel,
                                  const SizedBox(height: 16),
                                  selectedPanel,
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: formWidget),
                          ],
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          calendarPanel,
                          const SizedBox(height: 16),
                          selectedPanel,
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  final String? createdLabel;
  final String? tips;
  final DateTime? completedAt;
  final bool canComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onComplete;

  const _ScheduleTile({
    required this.groupName,
    required this.subtitle,
    required this.createdLabel,
    required this.tips,
    required this.completedAt,
    required this.canComplete,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
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
          Row(
            children: [
              Expanded(
                child: Text(
                  groupName,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB71C1C),
                  ),
                ),
              ),
              if (completedAt != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Completed',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ),
              if (completedAt == null && canComplete && onComplete != null)
                IconButton(
                  onPressed: onComplete,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  color: const Color(0xFF2E7D32),
                  tooltip: 'Mark as done',
                ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                color: const Color(0xFFB71C1C),
                tooltip: 'Edit schedule',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: Colors.redAccent,
                tooltip: 'Delete schedule',
              ),
            ],
          ),
          Text(
            subtitle,
            style: GoogleFonts.manrope(fontSize: 13, color: Colors.black54),
          ),
          if ((createdLabel ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              createdLabel!,
              style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (completedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Completed ${completedAt!.toLocal().month}/${completedAt!.toLocal().day}/${completedAt!.toLocal().year} at ${completedAt!.toLocal().hour % 12 == 0 ? 12 : completedAt!.toLocal().hour % 12}:${completedAt!.toLocal().minute.toString().padLeft(2, '0')} ${completedAt!.toLocal().hour >= 12 ? 'PM' : 'AM'}',
              style: GoogleFonts.manrope(fontSize: 12, color: Colors.black54),
            ),
          ],
          if ((tips ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tips!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }
}
