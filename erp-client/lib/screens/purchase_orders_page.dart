import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import '../navigation/mobile_modules.dart';
import '../navigation/transaction_detail_host.dart';
import '../navigation/transaction_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  bool _loading = true;
  bool _fromCache = false;
  String? _busyId;
  String? _error;
  String? _offlineLabel;
  String _filter = 'action';
  List<Map<String, dynamic>> _rows = [];
  TransactionLists _lists = const TransactionLists();

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'action':
        return _rows
            .where((r) => r['status'] != 'fully_received' && r['status'] != 'cancelled')
            .toList();
      case 'completed':
        return _rows.where((r) => r['status'] == 'fully_received').toList();
      default:
        return _rows;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      _offlineLabel = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getList('/purchase-orders'),
        TransactionLists.load(widget.api),
      ]);
      final data = results[0] as List<dynamic>;
      final lists = results[1] as TransactionLists;
      await OfflineCache.saveList(OfflineCache.purchaseOrders, data);
      if (!mounted) return;
      setState(() {
        _rows = data.cast<Map<String, dynamic>>();
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.purchaseOrders);
      final lists = await TransactionLists.fromCache();
      if (!mounted) return;
      if (cached.rows.isNotEmpty) {
        setState(() {
          _rows = cached.rows;
          _lists = lists;
          _fromCache = true;
          _offlineLabel = OfflineCache.staleLabel(cached.savedAt);
          _error = friendlyApiError(error);
          _loading = false;
        });
      } else {
        setState(() {
          _error = friendlyApiError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _receiveItems(Map<String, dynamic> row, {bool popCurrentRoute = false}) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldDbId(row);
    if (id.isEmpty || _busyId != null) return;

    final existing = findReceivingForPo(row, _lists);
    if (existing != null) {
      await openCreatedTransaction(
        context,
        widget.api,
        MobileModule.receiving,
        existing,
        popCurrentRoute: popCurrentRoute,
        offline: _fromCache,
      );
      return;
    }

    if (!canReceivePurchaseOrder(row, _lists)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This purchase order cannot receive items.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create receiving?'),
        content: Text('Start receiving for ${row['id'] ?? id}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyId = id);
    try {
      final response = await widget.api.post('/purchase-orders/$id/receivings');
      if (!mounted) return;
      final receiving = recordFromPayload(response);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiving created.')),
      );
      await _load();
      if (receiving != null && mounted) {
        final resolved = await resolveCreatedTransactionRecord(
          widget.api,
          MobileModule.receiving,
          receiving,
        );
        if (!mounted) return;
        await openCreatedTransaction(
          context,
          widget.api,
          MobileModule.receiving,
          resolved,
          popCurrentRoute: popCurrentRoute,
          offline: _fromCache,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.maroon,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          FieldFilterBar(
            value: _filter,
            options: const [
              (id: 'action', label: 'Open'),
              (id: 'completed', label: 'Completed'),
              (id: 'all', label: 'All'),
            ],
            onChanged: (value) => setState(() => _filter = value),
          ),
          if (_fromCache && _offlineLabel != null)
            FieldOfflineBanner(
              label: _offlineLabel!,
              hint: OfflineCache.offlineReconnectHint,
            ),
          if (!_lists.crossModuleRulesReliable && !_loading)
            const FieldPartialCacheBanner(),
          if (_error != null && !_fromCache) FieldErrorBanner(message: _error!, onRetry: _load),
          if (visible.isEmpty && (_error == null || _fromCache))
            const FieldEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'No purchase orders',
            ),
          ...visible.map((row) {
            final id = fieldDbId(row);
            final busy = _busyId == id;
            final canReceive = _lists.crossModuleRulesReliable && canReceivePurchaseOrder(row, _lists);

            return Card(
              child: InkWell(
                onTap: () => pushTransactionDetail(
                  context,
                  widget.api,
                  MobileModule.purchaseOrders,
                  row,
                  offline: _fromCache,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row['id']?.toString() ?? 'PO',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          FieldStatusChip(row['status']?.toString()),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(row['supplierName']?.toString() ?? 'Supplier —'),
                      Text(
                        '${row['displayDate'] ?? row['date'] ?? '—'} · '
                        'Ref: ${row['referenceQuotationId'] ?? '—'} · '
                        '${fieldFormatMoney(row['total'])}',
                      ),
                      if (canReceive) ...[
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: busy || _fromCache ? null : () => _receiveItems(row),
                          child: Text(busy ? 'Working…' : 'Receive items'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class PurchaseOrderDetailPage extends StatelessWidget {
  const PurchaseOrderDetailPage({
    super.key,
    required this.api,
    required this.order,
    required this.canReceive,
    this.onReceive,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
    this.offline = false,
  });

  final ApiClient api;
  final Map<String, dynamic> order;
  final bool canReceive;
  final Future<void> Function()? onReceive;
  final String? workflowNotice;
  final bool workflowNoticeLoading;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return FieldDetailScaffold(
      title: order['id']?.toString() ?? 'Purchase order',
      subtitle: order['supplierName']?.toString() ?? 'Supplier —',
      status: order['status']?.toString(),
      workflowNotice: workflowNotice,
      workflowNoticeLoading: workflowNoticeLoading,
      secondaryActions: [
        PrintDocumentButton(
          onPrint: () => printPurchaseOrder(context, api, order),
          label: 'Print PDF',
          enabled: !offline,
        ),
      ],
      primaryActions: [
        if (canReceive && onReceive != null)
          FilledButton(
            onPressed: () async => onReceive!(),
            child: const Text('Receive items'),
          ),
      ],
      children: [
        FieldDetailMeta(
          rows: [
            (label: 'Date', value: '${order['displayDate'] ?? order['date'] ?? '—'}'),
            (
              label: 'Quotation',
              value: '${order['referenceQuotationNo'] ?? order['referenceQuotationId'] ?? '—'}',
            ),
            (label: 'Total', value: fieldFormatMoney(order['total'])),
          ],
        ),
        const SizedBox(height: 16),
        const FieldSectionTitle('Line items'),
        FieldLineItems(items: items),
      ],
    );
  }
}
