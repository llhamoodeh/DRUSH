import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/group_item.dart';
import '../models/group_leaderboard_entry.dart';
import '../models/group_member.dart';
import '../models/group_task.dart';
import '../models/schedule_item.dart';
import '../models/streak_leaderboard_entry.dart';
import '../models/user_streak.dart';
import '../shared/globals.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class BackendService {
  const BackendService();

  void _logRequest(String method, Uri url, {Object? body}) {
    debugPrint('[API] $method $url');
    if (body != null) {
      debugPrint('[API] payload: $body');
    }
  }

  void _logResponse(Uri url, http.Response response) {
    debugPrint('[API] response ${response.statusCode} $url');
    debugPrint('[API] body: ${response.body}');
  }

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<GroupItem>> fetchGroups(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/groups');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load groups.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(GroupItem.fromJson)
        .toList();
  }

  Future<List<GroupItem>> fetchUserGroups(
    String token, {
    int? userId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/mine');
    _logRequest('GET', url);
    try {
      final response = await http
          .get(url, headers: _headers(token))
          .timeout(const Duration(seconds: 12));
      _logResponse(url, response);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .whereType<Map<String, dynamic>>()
            .map(GroupItem.fromJson)
            .toList();
      }

      if (response.statusCode == 404 && userId != null) {
        return _fetchUserGroupsFallback(token: token, userId: userId);
      }

      if (userId != null && response.statusCode >= 500) {
        return _fetchUserGroupsFallback(token: token, userId: userId);
      }

      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load your groups.',
      );
    } catch (error) {
      if (userId != null) {
        debugPrint('[API] /groups/mine failed, using fallback: $error');
        return _fetchUserGroupsFallback(token: token, userId: userId);
      }

      rethrow;
    }
  }

  Future<List<GroupItem>> _fetchUserGroupsFallback({
    required String token,
    required int userId,
  }) async {
    final groups = await fetchGroups(token);
    final groupIds = await _fetchUserGroupIds(token: token, userId: userId);
    return groups.where((group) => groupIds.contains(group.id)).toList();
  }

  Future<Set<int>> _fetchUserGroupIds({
    required String token,
    required int userId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/grouppart');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load group membership.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final groupIds = <int>{};
    for (final entry in data.whereType<Map<String, dynamic>>()) {
      final memberId = entry['userid'] ?? entry['userId'];
      final groupId = entry['groupid'] ?? entry['groupId'];

      final parsedMember = memberId is int
          ? memberId
          : int.tryParse('$memberId') ?? 0;
      if (parsedMember != userId) {
        continue;
      }

      final parsedGroup = groupId is int
          ? groupId
          : int.tryParse('$groupId') ?? 0;
      if (parsedGroup > 0) {
        groupIds.add(parsedGroup);
      }
    }

    return groupIds;
  }

  Future<GroupItem> createGroup({
    required String token,
    required String name,
    required int creatorId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups');
    final payload = {
      'name': name,
      'creatorid': creatorId,
    };
    _logRequest('POST', url, body: payload);
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    _logResponse(url, response);

    if (response.statusCode != 201) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to create group.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupItem.fromJson(data);
  }

  Future<List<GroupMember>> fetchGroupMembers({
    required String token,
    required int groupId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/$groupId/members');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractMessage(response.body) ?? 'Failed to load group members.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList();
  }

  Future<GroupMember> addGroupMember({
    required String token,
    required int groupId,
    required String email,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/$groupId/members');
    final payload = {'email': email};
    _logRequest('POST', url, body: payload);
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    _logResponse(url, response);

    if (response.statusCode != 201) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to add member.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupMember.fromJson(data);
  }

  Future<void> removeGroupMember({
    required String token,
    required int groupId,
    required int userId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/$groupId/members/$userId');
    _logRequest('DELETE', url);
    final response = await http.delete(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to remove member.',
      );
    }
  }

  Future<List<GroupTask>> fetchGroupTasks({
    required String token,
    required int groupId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/$groupId/tasks');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractMessage(response.body) ?? 'Failed to load group tasks.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(GroupTask.fromJson)
        .toList();
  }

  Future<void> completeGroupTask({
    required String token,
    required int groupId,
    required int scheduleId,
  }) async {
    final url = Uri.parse(
      '$apiBaseUrl/api/groups/$groupId/tasks/$scheduleId/complete',
    );
    _logRequest('POST', url);
    final response = await http.post(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to complete task.',
      );
    }
  }

  Future<void> completeScheduleTask({
    required String token,
    required int scheduleId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/schedule/$scheduleId/complete');
    _logRequest('POST', url);
    final response = await http.post(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to complete task.',
      );
    }
  }

  Future<List<GroupLeaderboardEntry>> fetchGroupLeaderboard({
    required String token,
    required int groupId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/groups/$groupId/leaderboard');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractMessage(response.body) ?? 'Failed to load leaderboard.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(GroupLeaderboardEntry.fromJson)
        .toList();
  }

  Future<List<ScheduleItem>> fetchSchedules(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/schedule');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load schedules.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ScheduleItem.fromJson)
        .toList();
  }

  Future<ScheduleItem> createSchedule({
    required String token,
    required int userId,
    int? groupId,
    required DateTime startDateTime,
    required DateTime endDateTime,
    required DateTime createdAt,
    required int createdBy,
    String? tips,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/schedule');
    final payload = <String, Object?>{
      'userid': userId,
      'startdatetime': _formatDateTime(startDateTime),
      'enddatetime': _formatDateTime(endDateTime),
      'createdat': _formatDateTime(createdAt),
      'createdby': createdBy,
      'tips': tips,
    };
    if (groupId != null) {
      payload['groupid'] = groupId;
    }
    _logRequest('POST', url, body: payload);
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    _logResponse(url, response);

    if (response.statusCode != 201) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to create schedule.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ScheduleItem.fromJson(data);
  }

  Future<ScheduleItem> updateSchedule({
    required String token,
    required ScheduleItem original,
    required int userId,
    int? groupId,
    required DateTime startDateTime,
    required DateTime endDateTime,
    required DateTime createdAt,
    required int createdBy,
    String? tips,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/schedule/${original.id}');
    final payload = {
      'userid': userId,
      'groupid': groupId,
      'startdatetime': _formatDateTime(startDateTime),
      'enddatetime': _formatDateTime(endDateTime),
      'createdat': _formatDateTime(createdAt),
      'createdby': createdBy,
      'tips': tips,
    };
    _logRequest('PUT', url, body: payload);
    final response = await http.put(
      url,
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to update schedule.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ScheduleItem.fromJson(data);
  }

  Future<void> deleteSchedule({
    required String token,
    required int scheduleId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/schedule/$scheduleId');
    _logRequest('DELETE', url);
    final response = await http.delete(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to delete schedule.',
      );
    }
  }

  Future<List<ChatMessage>> fetchChatMessages(
    String token, {
    int limit = 60,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/chat?limit=$limit');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load chat messages.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  Future<List<ChatMessage>> sendChatMessage({
    required String token,
    required String message,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/chat');
    final payload = {'message': message};
    _logRequest('POST', url, body: payload);
    final response = await http.post(
      url,
      headers: _headers(token),
      body: jsonEncode(payload),
    );
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to send message.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['messages'] is List) {
      final data = decoded['messages'] as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    }

    return const <ChatMessage>[];
  }

  Future<void> deleteChatHistory(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/chat');
    _logRequest('DELETE', url);
    final response = await http.delete(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to clear chat history.',
      );
    }
  }

  Future<void> deleteChatMessage({
    required String token,
    required int id,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/chat/$id');
    _logRequest('DELETE', url);
    final response = await http.delete(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to delete message.',
      );
    }
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}T'
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  String? _extractMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<int> fetchUserCoins(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/auth/me/coins');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load coins.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['coins'] as num?)?.toInt() ?? 0;
  }

  Future<UserStreak> fetchUserStreak(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/auth/me/streak');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load streak.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UserStreak.fromJson(data);
  }

  Future<List<StreakLeaderboardEntry>> fetchStreakLeaderboard(
    String token,
  ) async {
    final url = Uri.parse('$apiBaseUrl/api/auth/leaderboard');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load streak leaderboard.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(StreakLeaderboardEntry.fromJson)
        .toList();
  }

  // ── Vouchers ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchVouchers(String token) async {
    final url = Uri.parse('$apiBaseUrl/api/vouchers');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load vouchers.',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> redeemVoucher({
    required String token,
    required String voucherId,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/vouchers/$voucherId/redeem');
    _logRequest('POST', url);
    final response = await http.post(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    final msg = _extractMessage(response.body) ?? 'Failed to redeem voucher.';
    throw ApiException(response.statusCode, msg);
  }

  Future<List<Map<String, dynamic>>> fetchRedemptionHistory(
    String token,
  ) async {
    final url = Uri.parse('$apiBaseUrl/api/vouchers/history');
    _logRequest('GET', url);
    final response = await http.get(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to load history.',
      );
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().toList();
  }
}
