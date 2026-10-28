import 'package:shared_preferences/shared_preferences.dart';

/// Resolves API base URL: saved phone setting overrides [builtinDefault] from `--dart-define`.
class ApiSettings {
  ApiSettings._();

  static const _prefKey = 'rc_api_base_url';

  static const String builtinDefault = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/mobile',
  );

  static String _current = builtinDefault;

  static String get current => _current;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _current = normalize(saved ?? builtinDefault);
  }

  static Future<void> save(String input) async {
    _current = normalize(input);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _current);
  }

  /// Removes saved server URL; next [load] uses [builtinDefault].
  static Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    _current = normalize(builtinDefault);
  }

  /// Ensures `http(s)://host:port/api` with no trailing slash.
  static String normalize(String raw) {
    var url = raw.trim();
    if (url.isEmpty) {
      return normalize(builtinDefault);
    }
    if (!url.contains('://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    final lower = url.toLowerCase();
    if (lower.endsWith('/api/mobile')) {
      return url;
    }
    if (lower.endsWith('/api')) {
      return '$url/mobile';
    }
    return '$url/api/mobile';
  }

  /// Human hint for login screen (host + port, no path).
  static String displayHostPort(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }
}
