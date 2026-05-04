class ScheduleItem {
  final int userId;
  final int groupId;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final DateTime? createdAt;
  final int? createdBy;
  final String? tips;
  final DateTime? completedAt;
  final int? completedBy;

  const ScheduleItem({
    required this.userId,
    required this.groupId,
    required this.startDateTime,
    required this.endDateTime,
    required this.createdAt,
    required this.createdBy,
    required this.tips,
    this.completedAt,
    this.completedBy,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      userId: _asInt(json['userid']),
      groupId: _asInt(json['groupid']),
      startDateTime: DateTime.parse(json['startdatetime'].toString()),
      endDateTime: DateTime.parse(json['enddatetime'].toString()),
      createdAt: _parseDate(json['createdat'] ?? json['creeatedat']),
      createdBy: _asNullableInt(json['createdby']),
      tips: json['tips']?.toString(),
      completedAt: _parseDate(json['completedat'] ?? json['completedAt']),
      completedBy: _asNullableInt(json['completedby'] ?? json['completedBy']),
    );
  }

  bool occursOn(DateTime date) {
    return startDateTime.year == date.year &&
        startDateTime.month == date.month &&
        startDateTime.day == date.day;
  }

  bool isUpcoming(DateTime now) => endDateTime.isAfter(now);

  bool get isCompleted => completedAt != null;

  static DateTime? _parseDate(Object? value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }
}
