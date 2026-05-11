import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result of AI task-completion verification.
class TaskVerificationResult {
  final bool approved;
  final String reason;

  const TaskVerificationResult({required this.approved, required this.reason});
}

/// Service that talks to the AI image-analysis and chat endpoints to verify
/// that a task has been completed or partially completed (≥ 20 %).
class TaskVerificationService {
  static const String _analyzeUrl = 'http://159.203.179.118:8000/analyze';
  static const String _chatUrl = 'http://159.203.179.118/chat';
  static const Duration _requestTimeout = Duration(seconds: 60);

  const TaskVerificationService();

  /// Upload [imageFile] to the /analyze endpoint and return the caption.
  Future<String> analyzeImage(File imageFile) async {
    final uri = Uri.parse(_analyzeUrl);
    debugPrint('[TaskVerification] POST $uri');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final streamedResponse = await request.send().timeout(
      _requestTimeout,
      onTimeout: () => throw TimeoutException(
        'Image analysis timed out. Please try again.',
      ),
    );
    final response = await http.Response.fromStream(streamedResponse);

    debugPrint('[TaskVerification] analyze response ${response.statusCode}');
    debugPrint('[TaskVerification] analyze body: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception(
        'Image analysis failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final caption = data['caption'] as String? ?? '';
    return caption;
  }

  /// Send the before/after captions together with the task description to the
  /// /chat endpoint and decide whether the task is at least 20 % complete or
  /// contextually similar.
  Future<TaskVerificationResult> validateTaskCompletion({
    required String beforeCaption,
    required String afterCaption,
    required String taskDescription,
  }) async {
    final prompt = '''You are a task-completion verification assistant. 
A user claims they have completed a task. You are given:

TASK DESCRIPTION: $taskDescription

BEFORE photo description: $beforeCaption

AFTER photo description: $afterCaption

Based on the descriptions above, estimate:
- confidence: how likely it is that the task or any meaningful part of it was completed (0-100)
- similarity: how similar the after context is to the task description (0-100)

IMPORTANT: The client will auto-approve if confidence >= 20 or similarity >= 20.
Reply ONLY with a JSON object in this exact format (no markdown, no extra text):
{"approved": true, "reason": "short explanation", "confidence": 0, "similarity": 0}''';

    final uri = Uri.parse(_chatUrl);
    debugPrint('[TaskVerification] POST $uri');

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': prompt}),
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(
            'Verification timed out. Please try again.',
          ),
        );

    debugPrint('[TaskVerification] chat response ${response.statusCode}');
    debugPrint('[TaskVerification] chat body: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception(
        'Chat verification failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawReply = (data['reply'] as String? ?? '').trim();
    final reply = _stripCodeFence(rawReply);

    // Try to parse the reply as JSON first.
    try {
      final parsed = jsonDecode(reply) as Map<String, dynamic>;
      final approved = parsed['approved'] == true;
      final reason = parsed['reason']?.toString() ?? reply;
      final confidence = _parsePercent(parsed['confidence']);
      final similarity = _parsePercent(parsed['similarity']);
      final meetsPartialThreshold =
          (confidence ?? 0) >= 20 || (similarity ?? 0) >= 20;
      return TaskVerificationResult(
        approved: approved || meetsPartialThreshold,
        reason: reason,
      );
    } catch (_) {
      // Fallback: heuristic on the raw reply text.
      final lower = reply.toLowerCase();
      final approved = lower.contains('"approved": true') ||
          lower.contains('"approved":true') ||
          lower.contains('approved');
      final inferredPercent = _extractPercentFromText(lower);
      final meetsPartialThreshold = (inferredPercent ?? 0) >= 20;
      return TaskVerificationResult(
        approved: (approved &&
                !lower.contains('"approved": false') &&
                !lower.contains('"approved":false')) ||
            meetsPartialThreshold,
        reason: reply,
      );
    }
  }

  String _stripCodeFence(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('```')) {
      return trimmed;
    }

    final fenceStart = trimmed.indexOf('\n');
    if (fenceStart == -1) {
      return trimmed.replaceAll('```', '').trim();
    }

    final fenceEnd = trimmed.lastIndexOf('```');
    if (fenceEnd == -1 || fenceEnd <= fenceStart) {
      return trimmed.substring(fenceStart + 1).trim();
    }

    return trimmed.substring(fenceStart + 1, fenceEnd).trim();
  }

  double? _parsePercent(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return _normalizePercent(value.toDouble());
    }
    if (value is String) {
      final cleaned = value.replaceAll('%', '').trim();
      final parsed = double.tryParse(cleaned);
      if (parsed == null) {
        return null;
      }
      return _normalizePercent(parsed);
    }
    return null;
  }

  double _normalizePercent(double value) {
    if (value <= 1) {
      return value * 100;
    }
    return value;
  }

  double? _extractPercentFromText(String text) {
    final patterns = <RegExp>[
      RegExp(r'confidence[^0-9]*([0-9]+(?:\.[0-9]+)?)'),
      RegExp(r'similarity[^0-9]*([0-9]+(?:\.[0-9]+)?)'),
      RegExp(r'similar[^0-9]*([0-9]+(?:\.[0-9]+)?)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }
      final raw = match.group(1);
      if (raw == null) {
        continue;
      }
      final parsed = double.tryParse(raw);
      if (parsed == null) {
        continue;
      }
      return _normalizePercent(parsed);
    }
    return null;
  }
}
