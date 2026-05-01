import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../shared/globals.dart';

class AuthSession {
  final String token;
  final User user;

  const AuthSession({
    required this.token,
    required this.user,
  });
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$apiBaseUrl/api/auth/login');
    final response = await http.post(
      url,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw AuthException(_extractMessage(response.body) ?? 'Login failed.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = (data['token'] ?? '').toString();

    if (token.isEmpty) {
      throw const AuthException('Login succeeded but no token was returned.');
    }

    final userJson = data['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const AuthException('Login succeeded but user data was missing.');
    }

    return AuthSession(
      token: token,
      user: User.fromJson(userJson),
    );
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
