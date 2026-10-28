import 'api_client.dart';
import 'offline_cache.dart';

class TransactionLists {
  const TransactionLists({
    this.purchaseOrders = const [],
    this.receivings = const [],
    this.outslips = const [],
    this.deliveryReceipts = const [],
    this.billings = const [],
    this.crossModuleRulesReliable = true,
  });

  final List<Map<String, dynamic>> purchaseOrders;
  final List<Map<String, dynamic>> receivings;
  final List<Map<String, dynamic>> outslips;
  final List<Map<String, dynamic>> deliveryReceipts;
  final List<Map<String, dynamic>> billings;

  /// False when built from stale/partial offline cache — hide cross-module workflow buttons.
  final bool crossModuleRulesReliable;

  static Future<TransactionLists> load(ApiClient api) async {
    final results = await Future.wait([
      api.getList('/purchase-orders'),
      api.getList('/receivings'),
      api.getList('/outslips'),
      api.getList('/delivery-receipts'),
      api.getList('/billings'),
    ]);

    return TransactionLists(
      purchaseOrders: results[0].cast<Map<String, dynamic>>(),
      receivings: results[1].cast<Map<String, dynamic>>(),
      outslips: results[2].cast<Map<String, dynamic>>(),
      deliveryReceipts: results[3].cast<Map<String, dynamic>>(),
      billings: results[4].cast<Map<String, dynamic>>(),
    );
  }

  static Future<TransactionLists> fromCache() async {
    final results = await Future.wait([
      OfflineCache.loadList(OfflineCache.purchaseOrders),
      OfflineCache.loadList(OfflineCache.receivings),
      OfflineCache.loadList(OfflineCache.outslips),
      OfflineCache.loadList(OfflineCache.deliveries),
      OfflineCache.loadList(OfflineCache.billings),
    ]);

    final reliable = results.every((entry) => entry.savedAt != null);

    return TransactionLists(
      purchaseOrders: results[0].rows,
      receivings: results[1].rows,
      outslips: results[2].rows,
      deliveryReceipts: results[3].rows,
      billings: results[4].rows,
      crossModuleRulesReliable: reliable,
    );
  }
}
