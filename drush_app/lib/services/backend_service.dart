import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/group_item.dart';
import '../models/schedule_item.dart';
import '../shared/globals.dart';

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
      'creeatedat': _formatDateTime(createdAt),
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
    final effectiveGroupId = groupId ?? original.groupId;
    final keyChanged =
        original.userId != userId ||
        original.groupId != effectiveGroupId ||
        !_sameMoment(original.startDateTime, startDateTime);

    if (keyChanged) {
      await deleteSchedule(
        token: token,
        userId: original.userId,
        groupId: original.groupId,
        startDateTime: original.startDateTime,
      );

      return createSchedule(
        token: token,
        userId: userId,
        groupId: groupId,
        startDateTime: startDateTime,
        endDateTime: endDateTime,
        createdAt: createdAt,
        createdBy: createdBy,
        tips: tips,
      );
    }

    final url = Uri.parse(
      '$apiBaseUrl/api/schedule/${original.userId}/${original.groupId}/${Uri.encodeComponent(_formatDateTime(original.startDateTime))}',
    );
    final payload = {
      'enddatetime': _formatDateTime(endDateTime),
      'creeatedat': _formatDateTime(createdAt),
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
    required int userId,
    required int groupId,
    required DateTime startDateTime,
  }) async {
    final url = Uri.parse(
      '$apiBaseUrl/api/schedule/$userId/$groupId/${Uri.encodeComponent(_formatDateTime(startDateTime))}',
    );
    _logRequest('DELETE', url);
    final response = await http.delete(url, headers: _headers(token));
    _logResponse(url, response);

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ?? 'Failed to delete schedule.',
      );
    }
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}T'
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  bool _sameMoment(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day &&
        left.hour == right.hour &&
        left.minute == right.minute &&
        left.second == right.second;
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
}
