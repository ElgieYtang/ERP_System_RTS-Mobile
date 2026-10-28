import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_discovery.dart';
import 'api_settings.dart';
import 'offline_cache.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient();

  static const _requestTimeout = Duration(seconds: 30);

  static const _tokenKey = 'rc_erp_token';
  static const _userKey = 'rc_erp_user';

  /// Called when the server rejects the session (401). Wire to [AuthState].
  void Function(String message)? onSessionExpired;

  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  String get baseUrl => ApiSettings.current;

  Future<void> ensureConfigured() async {
    await ApiSettings.load();
    await _autoDiscoverServerIfNeeded();
  }

  /// When the saved URL is unreachable (e.g. 10.0.2.2 on a real phone), find the PC on Wi‑Fi.
  Future<void> _autoDiscoverServerIfNeeded() async {
    final reachability = await pingHealth(
      timeout: const Duration(seconds: 4),
    );
    if (reachability == null) return;

    final discovered = await ApiDiscovery.discover();
    if (discovered == null) return;

    await ApiSettings.save(discovered);
    await pingHealth(timeout: const Duration(seconds: 4));
  }

  Future<void> updateBaseUrl(String input) async {
    await ApiSettings.save(input);
  }

  /// Resets saved API host and wipes offline list caches on this phone.
  Future<void> resetSavedConnection() async {
    await ApiSettings.clearSaved();
    await OfflineCache.clearAll();
  }

  /// Checks `GET /api/health` without auth. Returns null on success.
  Future<String?> pingHealth({
    String? baseUrlOverride,
    Duration timeout = _requestTimeout,
  }) async {
    final base = ApiSettings.normalize(baseUrlOverride ?? ApiSettings.current);
    final uri = Uri.parse('$base/health');
    try {
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      return 'Server returned ${response.statusCode}';
    } catch (error) {
      if (error is ApiException) {
        return error.message;
      }
      return error.toString();
    }
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null) {
      _user = jsonDecode(rawUser) as Map<String, dynamic>;
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token == null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      return;
    }
    await prefs.setString(_tokenKey, _token!);
    if (_user != null) {
      await prefs.setString(_userKey, jsonEncode(_user));
    }
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiSettings.current}$normalized').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers();
    late http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(_requestTimeout);
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ).timeout(_requestTimeout);
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ).timeout(_requestTimeout);
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(_requestTimeout);
        default:
          throw ApiException('Unsupported method $method');
      }
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        'Network error talking to ${ApiSettings.current}: $error',
      );
    }

    return _decode(response);
  }

  Future<dynamic> _decode(http.Response response) async {
    if (response.statusCode == 401) {
      await _expireSession();
      throw ApiException('Session expired. Please sign in again.', statusCode: 401);
    }

    final raw = response.body.isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(raw);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['message'] is String
          ? decoded['message'] as String
          : 'Request failed (${response.statusCode})';
      throw ApiException(message, statusCode: response.statusCode);
    }

    return decoded;
  }

  Future<Map<String, dynamic>> login(String login, String password) async {
    final payload = await request(
      'POST',
      '/auth/login',
      body: {'login': login, 'password': password},
    ) as Map<String, dynamic>;

    _token = payload['token'] as String?;
    _user = payload['user'] as Map<String, dynamic>?;
    await _persistSession();
    return payload;
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        await request('POST', '/auth/logout');
      }
    } catch (_) {
      // Clear local session anyway.
    }
    await clearSession();
  }

  Future<void> _expireSession() async {
    const message = 'Session expired. Please sign in again.';
    await clearSession();
    onSessionExpired?.call(message);
  }

  Future<void> clearSession() async {
    _token = null;
    _user = null;
    await _persistSession();
  }

  Future<Map<String, dynamic>> me() async {
    final payload = await request('GET', '/auth/me') as Map<String, dynamic>;
    _user = payload['user'] as Map<String, dynamic>?;
    await _persistSession();
    return payload;
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final payload = await request('GET', path, query: query) as Map<String, dynamic>;
    return (payload['data'] as List<dynamic>? ?? const []);
  }

  Future<Map<String, dynamic>> getOne(String path) async {
    final payload = await request('GET', path) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    final message = payload['message'] is String
        ? payload['message'] as String
        : 'Record not found.';
    throw ApiException(message, statusCode: 404);
  }

  Future<Map<String, dynamic>> getData(
    String path, {
    Map<String, String>? query,
  }) async {
    final payload = await request('GET', path, query: query) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) async {
    final payload = await request('POST', path, body: body) as Map<String, dynamic>;
    return payload;
  }

  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) async {
    final payload = await request('PUT', path, body: body) as Map<String, dynamic>;
    return payload;
  }

  Future<Uint8List> getBytes(String path) async {
    final uri = _uri(path);
    final response = await http.get(uri, headers: _headers(json: false));
    if (response.statusCode == 401) {
      await _expireSession();
      throw ApiException('Session expired. Please sign in again.', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Could not download file.', statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadPhotos({
    required String accomplishmentId,
    required List<({String filename, Uint8List bytes})> files,
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final uri = _uri('/accomplishments/$accomplishmentId/photos');
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(_headers(json: false));

        for (final file in files) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'photos[]',
              file.bytes,
              filename: file.filename,
              contentType: MediaType('image', 'jpeg'),
            ),
          );
        }

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);
        return await _decode(response) as Map<String, dynamic>;
      } on ApiException catch (error) {
        lastError = error;
        // Don't retry auth / validation failures.
        if (error.statusCode == 401 ||
            error.statusCode == 403 ||
            error.statusCode == 422 ||
            attempt == maxAttempts) {
          rethrow;
        }
      } catch (error) {
        lastError = error;
        if (attempt == maxAttempts) {
          throw ApiException(
            'Network error uploading photos to ${ApiSettings.current}: $error',
          );
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }

    if (lastError is ApiException) {
      throw lastError;
    }
    throw ApiException('Photo upload failed after $maxAttempts attempts.');
  }
}
