class GroupItem {
  final int id;
  final String name;
  final int creatorId;
  final DateTime? creationDate;

  const GroupItem({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.creationDate,
  });

  factory GroupItem.fromJson(Map<String, dynamic> json) {
    final creationDateValue = json['creationDate'];

    return GroupItem(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      creatorId: _asInt(json['creatorid']),
      creationDate: creationDateValue == null
          ? null
          : DateTime.tryParse(creationDateValue.toString()),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
