import '../navigation/mobile_modules.dart';
import 'api_client.dart';
import 'api_errors.dart';
import 'home_counts.dart';

class DashboardRefresh {
  DashboardRefresh._();

  static const _attempts = 3;

  static Future<Map<MobileModule, int>> fetchModuleCounts(ApiClient api) async {
    await api.ensureConfigured();
    Object? statsError;
    for (var attempt = 0; attempt < _attempts; attempt++) {
      try {
        final stats = await api.getData('/dashboard/stats');
        return homeModuleCountsFromDashboardStats(stats);
      } catch (error) {
        statsError = error;
        if (attempt < _attempts - 1) {
          await Future<void>.delayed(Duration(milliseconds: 450 * (attempt + 1)));
        }
      }
    }

    try {
      return await _countsFromLiveLists(api);
    } catch (listError) {
      throw statsError ?? listError;
    }
  }

  static Future<Map<MobileModule, int>> _countsFromLiveLists(ApiClient api) async {
    final results = await Future.wait([
      api.getList('/quotations', query: const {'all': '1'}),
      api.getList('/purchase-orders', query: const {'all': '1'}),
      api.getList('/receivings', query: const {'all': '1'}),
      api.getList('/outslips', query: const {'all': '1'}),
      api.getList('/delivery-receipts', query: const {'all': '1'}),
      api.getList('/billings', query: const {'all': '1'}),
      api.getList('/accomplishments', query: const {'all': '1'}),
    ]);
    return computeHomeModuleCounts(
      quotations: results[0],
      purchaseOrders: results[1],
      receivings: results[2],
      outslips: results[3],
      deliveryReceipts: results[4],
      billings: results[5],
      accomplishments: results[6],
    );
  }

  /// Actionable message when live stats could not be loaded.
  static Future<String> describeFailure(ApiClient api, Object error) async {
    final pingError = await api.pingHealth();
    if (pingError == null) {
      return 'Server answered but dashboard failed to load. Pull down to retry, or sign out and sign in again.';
    }
    final base = friendlyApiError(error);
    if (base.toLowerCase().contains('cannot reach api')) {
      return '$base\nOpen profile → API server and verify your PC IP (same Wi‑Fi).';
    }
    return base;
  }
}
