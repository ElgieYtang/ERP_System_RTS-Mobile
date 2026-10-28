import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last-known list payloads for field screens when the API is unreachable.
class OfflineCache {
  OfflineCache._();

  static const receivings = 'rc_cache_receivings';
  static const outslips = 'rc_cache_outslips';
  static const deliveries = 'rc_cache_deliveries';
  static const accomplishments = 'rc_cache_accomplishments';
  static const quotations = 'rc_cache_quotations';
  static const purchaseOrders = 'rc_cache_purchase_orders';
  static const billings = 'rc_cache_billings';
  static const homeStats = 'rc_cache_home_stats';
  static const projects = 'rc_cache_projects';
  static const soaCustomers = 'rc_cache_soa_customers';

  static const _gatePassPrefix = 'rc_cache_gate_pass_';
  static const _soaReportPrefix = 'rc_cache_soa_';
  static const _accomplishmentDetailPrefix = 'rc_cache_accomplishment_';

  static String gatePassKey(String outslipRef) => '$_gatePassPrefix$outslipRef';

  static String soaReportKey(String customerId, {String? from, String? to}) =>
      '$_soaReportPrefix${customerId}_${from ?? 'any'}_${to ?? 'any'}';

  static String accomplishmentDetailKey(String reportId) =>
      '$_accomplishmentDetailPrefix$reportId';

  static Future<void> saveGatePass(String outslipRef, Map<String, dynamic> document) =>
      saveMap(gatePassKey(outslipRef), document);

  static Future<({Map<String, dynamic>? data, DateTime? savedAt})> loadGatePass(
    String outslipRef,
  ) =>
      loadMap(gatePassKey(outslipRef));

  static Future<void> saveSoaReport(
    String customerId, {
    String? from,
    String? to,
    required Map<String, dynamic> account,
  }) =>
      saveMap(soaReportKey(customerId, from: from, to: to), account);

  static Future<({Map<String, dynamic>? data, DateTime? savedAt})> loadSoaReport(
    String customerId, {
    String? from,
    String? to,
  }) =>
      loadMap(soaReportKey(customerId, from: from, to: to));

  static Future<void> saveAccomplishmentDetail(
    String reportId,
    Map<String, dynamic> report,
  ) =>
      saveMap(accomplishmentDetailKey(reportId), report);

  static Future<({Map<String, dynamic>? data, DateTime? savedAt})> loadAccomplishmentDetail(
    String reportId,
  ) =>
      loadMap(accomplishmentDetailKey(reportId));

  static String offlineReconnectHint = 'Pull down to refresh when back online.';

  static Future<void> saveList(String key, List<dynamic> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'data': rows,
      }),
    );
  }

  static Future<({List<Map<String, dynamic>> rows, DateTime? savedAt})> loadList(
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return (rows: <Map<String, dynamic>>[], savedAt: null);
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = (decoded['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final savedAtRaw = decoded['savedAt']?.toString();
      final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
      return (rows: data, savedAt: savedAt);
    } catch (_) {
      return (rows: <Map<String, dynamic>>[], savedAt: null);
    }
  }

  static Future<void> saveMap(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'data': value,
      }),
    );
  }

  static Future<({Map<String, dynamic>? data, DateTime? savedAt})> loadMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return (data: null, savedAt: null);
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : null;
      final savedAtRaw = decoded['savedAt']?.toString();
      final savedAt = savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
      return (data: data, savedAt: savedAt);
    } catch (_) {
      return (data: null, savedAt: null);
    }
  }

  /// Clears cached lists/reports saved on this device (not login token).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final toRemove = prefs
        .getKeys()
        .where((key) => key.startsWith('rc_cache_'))
        .toList();
    for (final key in toRemove) {
      await prefs.remove(key);
    }
  }

  static String staleLabel(DateTime? savedAt) {
    if (savedAt == null) return 'Showing saved data (offline)';
    final local = savedAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Offline — last updated ${local.month}/${local.day} $hh:$mm';
  }
}
