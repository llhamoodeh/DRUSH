import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

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

  Future<void> persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
  }

  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);

    if (token == null || token.isEmpty || userJson == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, dynamic>) {
        await clearSession();
        return null;
      }

      return AuthSession(
        token: token,
        user: User.fromJson(decoded),
      );
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
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
