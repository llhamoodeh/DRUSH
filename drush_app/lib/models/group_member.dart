class GroupMember {
  final int id;
  final String name;
  final String email;

  const GroupMember({
    required this.id,
    required this.name,
    required this.email,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;

    return GroupMember(
      id: id,
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }
}
