import '../services/api_settings.dart';

/// API base URL for the ERP Node API (erp-server).
///
/// Prefer [ApiSettings.current] (saved on device). This getter mirrors it for legacy imports.
class ApiConfig {
  static String get baseUrl => ApiSettings.current;
}
