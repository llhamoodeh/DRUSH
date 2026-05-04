import 'schedule_item.dart';

class GroupTask {
  final ScheduleItem schedule;
  final DateTime? completedAt;
  final int? completedBy;

  const GroupTask({
    required this.schedule,
    required this.completedAt,
    required this.completedBy,
  });

  bool get isCompleted => completedAt != null;

  factory GroupTask.fromJson(Map<String, dynamic> json) {
    final completedAtValue = json['completedat'] ?? json['completedAt'];
    final completedByValue = json['completedby'] ?? json['completedBy'];

    return GroupTask(
      schedule: ScheduleItem.fromJson(json),
      completedAt: completedAtValue == null
          ? null
          : DateTime.tryParse(completedAtValue.toString()),
      completedBy: completedByValue is int
          ? completedByValue
          : int.tryParse('${completedByValue ?? ''}'),
    );
  }
}
