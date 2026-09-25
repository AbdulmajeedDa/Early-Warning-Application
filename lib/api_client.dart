// Small networking helper for talking to the Laravel backend.
//
// This file does not touch any existing screen. It's the shared foundation
// screens will call into once they're wired to the real API.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'main.dart' show appLang;

class ApiConfig {
  // The permanent backend, hosted on Railway (always on, https).
  // For local development instead, temporarily swap this one line for:
  //   - Android emulator on this same PC -> 'http://10.0.2.2:8000/api/v1'
  //   - Real phone / another PC on the same network -> 'http://<this PC's LAN IP>:8000/api/v1'
  //   - Through an ngrok tunnel -> the https URL ngrok gives you, plus '/api/v1'
  //     (ngrok's free tier also needs the header 'ngrok-skip-browser-warning: true'
  //     on every request, otherwise it answers with an HTML warning page.)
  static const String baseUrl = 'https://early-warning-backend-production.up.railway.app/api/v1';
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class TokenStorage {
  static const _key = 'auth_token';
  static const _storage = FlutterSecureStorage();

  static Future<void> save(String token) async {
    await _storage.write(key: _key, value: token);
  }

  static Future<String?> read() async {
    return _storage.read(key: _key);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}

/// Keeps the last `user` object the server sent, so the app can still open
/// with the previous session's account details when there's no connectivity
/// at launch. Stored in secure storage (same as the auth token) since it's
/// personal data. Cleared on logout.
class UserCache {
  static const _key = 'cached_user_json';
  static const _storage = FlutterSecureStorage();

  static Future<void> save(Map<String, dynamic> json) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(json));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// Persists the two real toggles on the Permissions screen (notifications,
/// alert sound). Both default to enabled, matching that screen's original
/// hardcoded defaults, so a user who never opens the screen keeps today's
/// behavior.
class NotificationPrefs {
  static const _notificationsKey = 'notifications_enabled';
  static const _alertSoundKey = 'alert_sound_enabled';
  static const _storage = FlutterSecureStorage();

  static Future<bool> notificationsEnabled() async {
    return (await _storage.read(key: _notificationsKey)) != 'false';
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    await _storage.write(key: _notificationsKey, value: enabled.toString());
  }

  static Future<bool> alertSoundEnabled() async {
    return (await _storage.read(key: _alertSoundKey)) != 'false';
  }

  static Future<void> setAlertSoundEnabled(bool enabled) async {
    await _storage.write(key: _alertSoundKey, value: enabled.toString());
  }
}

class ApiClient {
  static Future<Map<String, String>> _authHeaders({bool auth = true}) async {
    // Lets the backend return validation/error messages in the language the
    // app is currently showing (see SetLocaleFromHeader on the Laravel side)
    // instead of always defaulting to English.
    final headers = {
      'Accept': 'application/json',
      'Accept-Language': appLang.value,
    };
    if (auth) {
      final token = await TokenStorage.read();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = await _authHeaders(auth: auth);
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    String message = 'Something went wrong. Please try again.';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['message'] is String) {
        message = body['message'] as String;
      }
      if (body['errors'] is Map && (body['errors'] as Map).isNotEmpty) {
        final firstField = (body['errors'] as Map).values.first;
        if (firstField is List && firstField.isNotEmpty) {
          message = firstField.first.toString();
        }
      }
    } catch (_) {
      // Response wasn't JSON (e.g. server crashed with an HTML error page) -
      // keep the generic message above.
    }
    throw ApiException(message, statusCode: response.statusCode);
  }

  static Future<Map<String, dynamic>> get(String path, {bool auth = true}) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: await _headers(auth: auth))
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  static Future<Map<String, dynamic>> delete(String path, Map<String, dynamic> body, {bool auth = true}) async {
    try {
      final request = http.Request('DELETE', Uri.parse('${ApiConfig.baseUrl}$path'))
        ..headers.addAll(await _headers(auth: auth))
        ..body = jsonEncode(body);
      final streamed = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }

  /// For endpoints that take a file alongside regular fields (e.g. a profile
  /// picture upload) - a plain JSON POST can't carry a file.
  static Future<Map<String, dynamic>> postMultipart(
    String path,
    Map<String, String> fields, {
    String? filePath,
    String fileField = 'file',
    bool auth = true,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}$path'))
        ..headers.addAll(await _authHeaders(auth: auth))
        ..fields.addAll(fields);
      if (filePath != null) {
        request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Could not reach the server. Check your connection.');
    }
  }
}
