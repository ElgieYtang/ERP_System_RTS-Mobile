import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../navigation/app_navigation.dart';
import '../navigation/mobile_modules.dart';
import '../navigation/transaction_detail_host.dart';
import '../navigation/transaction_navigation.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import '../theme/app_theme.dart';
import '../widgets/delivery_receipt_scan_panel.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';
import '../widgets/transaction_workflows.dart';

class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends State<DeliveriesPage> {
  bool _loading = true;
  bool _fromCache = false;
  String? _busyId;
  String? _error;
  String? _offlineLabel;
  String _filter = 'active';
  List<Map<String, dynamic>> _rows = [];
  TransactionLists _lists = const TransactionLists();

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'active':
        return _rows
            .where((r) => r['status'] == 'active' || r['status'] == 'out_for_delivery')
            .toList();
      case 'delivered':
        return _rows.where((r) => r['status'] == 'delivered').toList();
      default:
        return _rows;
    }
  }

  Future<void> _afterMutation(Map<String, dynamic>? updated) async {
    if (updated != null) {
      setState(() => _rows = upsertTransactionRow(_rows, updated));
    }
    try {
      final lists = await TransactionLists.load(widget.api);
      if (mounted) setState(() => _lists = lists);
    } catch (_) {}
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _fromCache = false;
        _offlineLabel = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.api.getList('/delivery-receipts'),
        TransactionLists.load(widget.api),
      ]);
      final data = results[0] as List<dynamic>;
      final lists = results[1] as TransactionLists;
      await OfflineCache.saveList(OfflineCache.deliveries, data);
      if (!mounted) return;
      setState(() {
        _rows = data.cast<Map<String, dynamic>>();
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.deliveries);
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

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }

    final id = row['dbId']?.toString() ?? row['id']?.toString();
    if (id == null || _busyId != null) return;
    if (!canUpdateDeliveryStatus(row, status)) return;

    setState(() => _busyId = id);
    try {
      final updated = await updateDeliveryStatus(context, widget.api, row, status);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _createBilling(Map<String, dynamic> row, {bool popCurrentRoute = false}) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldDbId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canCreateBillingFromDelivery(row, _lists)) return;
    setState(() => _busyId = id);
    try {
      final created = await confirmCreateBilling(context, widget.api, row);
      if (created != null) {
        await _load();
        if (!mounted) return;
        await openCreatedTransaction(
          context,
          widget.api,
          MobileModule.billing,
          created,
          popCurrentRoute: popCurrentRoute,
          offline: _fromCache,
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          FieldFilterBar(
            value: _filter,
            options: const [
              (id: 'active', label: 'Active'),
              (id: 'delivered', label: 'Delivered'),
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
            FieldEmptyState(
              icon: Icons.local_shipping_outlined,
              title: _filter == 'active' ? 'No active deliveries' : 'No deliveries',
            ),
          ...visible.map((row) {
            final id = row['dbId']?.toString() ?? row['id']?.toString() ?? '';
            final status = row['status']?.toString() ?? '';
            final itemCount = (row['items'] as List<dynamic>? ?? const []).length;
            final busy = _busyId == id;
            final showOut = canMarkDeliveryOutWithSerials(row);
            final showDelivered = canMarkDeliveryDeliveredWithSerials(row);
            final showBilling =
                _lists.crossModuleRulesReliable && canCreateBillingFromDelivery(row, _lists);

            return Card(
              child: InkWell(
                onTap: () async {
                  await pushTransactionDetail(
                    context,
                    widget.api,
                    MobileModule.deliveries,
                    row,
                    offline: _fromCache,
                  );
                  await _load();
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row['id']?.toString() ?? 'DR',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          FieldStatusChip(status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(row['customerName']?.toString().isNotEmpty == true
                          ? row['customerName'].toString()
                          : 'Customer —'),
                      Text(
                        '${row['displayDate'] ?? row['date'] ?? '—'} · '
                        'Outslip: ${row['referenceOutslipId'] ?? '—'} · '
                        '$itemCount item(s)',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (showOut)
                            FilledButton(
                              onPressed: busy || _fromCache
                                  ? null
                                  : () => _setStatus(row, 'out_for_delivery'),
                              child: Text(busy ? 'Updating…' : 'Out for delivery'),
                            ),
                          if (showDelivered)
                            FilledButton.tonal(
                              onPressed:
                                  busy || _fromCache ? null : () => _setStatus(row, 'delivered'),
                              child: const Text('Mark delivered'),
                            ),
                          if (showBilling)
                            FilledButton(
                              onPressed: busy || _fromCache ? null : () => _createBilling(row),
                              child: Text(busy ? 'Working…' : 'Create billing'),
                            ),
                        ],
                      ),
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

class DeliveryDetailPage extends StatefulWidget {
  const DeliveryDetailPage({
    super.key,
    required this.api,
    required this.delivery,
    this.popAfterMutations = true,
    this.onSetStatus,
    this.onCreateBilling,
    this.onDeliveryUpdated,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
    this.offline = false,
  });

  final ApiClient api;
  final Map<String, dynamic> delivery;
  final bool popAfterMutations;
  final Future<void> Function(String status)? onSetStatus;
  final Future<void> Function()? onCreateBilling;
  final ValueChanged<Map<String, dynamic>>? onDeliveryUpdated;
  final String? workflowNotice;
  final bool workflowNoticeLoading;
  final bool offline;

  @override
  State<DeliveryDetailPage> createState() => _DeliveryDetailPageState();
}

class _DeliveryDetailPageState extends State<DeliveryDetailPage> {
  late Map<String, dynamic> _delivery;
  bool _serialScanOpen = false;

  @override
  void initState() {
    super.initState();
    _delivery = Map<String, dynamic>.from(widget.delivery);
  }

  @override
  void didUpdateWidget(covariant DeliveryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delivery != widget.delivery) {
      setState(() {
        _delivery = Map<String, dynamic>.from(widget.delivery);
      });
    }
  }

  void _handleDeliveryUpdated(Map<String, dynamic> updated) {
    setState(() {
      _delivery = Map<String, dynamic>.from(updated);
      if (updated['status']?.toString() == 'out_for_delivery' &&
          deliverySerialsComplete(updated)) {
        _serialScanOpen = false;
      }
    });
    widget.onDeliveryUpdated?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final items = (_delivery['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final customer = _delivery['customerName']?.toString().isNotEmpty == true
        ? _delivery['customerName'].toString()
        : 'Customer —';
    final status = _delivery['status']?.toString() ?? '';
    final warehouseScan = canScanDeliverySerials(_delivery, offline: widget.offline);
    final serialsComplete = deliverySerialsComplete(_delivery);
    final canMarkNow = canMarkDeliveryDeliveredWithSerials(_delivery);

    if (warehouseScan || _serialScanOpen) {
      return DeliveryScanDetailView(
        api: widget.api,
        delivery: _delivery,
        popAfterMutations: widget.popAfterMutations,
        onSetStatus: widget.onSetStatus,
        onCreateBilling: widget.onCreateBilling,
        onSaved: _handleDeliveryUpdated,
        workflowNotice: widget.workflowNotice,
        workflowNoticeLoading: widget.workflowNoticeLoading,
        offline: widget.offline,
        onCloseScan: _serialScanOpen && status == 'out_for_delivery'
            ? () => setState(() => _serialScanOpen = false)
            : null,
      );
    }
    final title = _delivery['id']?.toString() ?? 'Delivery';

    return Scaffold(
      appBar: transactionAppBar(context, title: title, showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      customer,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (status.isNotEmpty) FieldStatusChip(status),
                ],
              ),
            ),
          ),
          if (status == 'out_for_delivery') ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.maroonLight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.local_shipping_outlined, color: AppTheme.maroon, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serialsComplete ? 'On the way to customer' : 'Finish serial capture',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            serialsComplete
                                ? 'Confirm delivery when the customer receives all items.'
                                : deliverySerialsBlockedMessage(),
                            style: const TextStyle(height: 1.45, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: FieldDetailMeta(
                rows: [
                  (label: 'Date', value: '${_delivery['displayDate'] ?? _delivery['date'] ?? '—'}'),
                  (label: 'Outslip', value: '${_delivery['referenceOutslipId'] ?? '—'}'),
                  if (_delivery['total'] != null)
                    (label: 'Total', value: fieldFormatMoney(_delivery['total'])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldSectionTitle('Line items'),
                  const SizedBox(height: 12),
                  FieldLineItems(items: items, showSerialProgress: true),
                ],
              ),
            ),
          ),
          if (widget.workflowNotice != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.maroonLight,
              child: ListTile(
                leading: widget.workflowNoticeLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.maroon),
                      )
                    : const Icon(Icons.info_outline_rounded, color: AppTheme.maroon),
                title: Text(
                  widget.workflowNotice!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.35),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (status == 'out_for_delivery' && !serialsComplete && !widget.offline) ...[
            FilledButton.icon(
              onPressed: () => setState(() => _serialScanOpen = true),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan serial numbers'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.onSetStatus != null && status == 'out_for_delivery') ...[
            FilledButton(
              onPressed: canMarkNow
                  ? () async {
                      await widget.onSetStatus!('delivered');
                      if (widget.popAfterMutations && context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(deliverySerialsBlockedMessage())),
                      );
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              child: const Text('Mark as delivered'),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.onSetStatus != null && canMarkDeliveryOutWithSerials(_delivery)) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                await widget.onSetStatus!('out_for_delivery');
                if (widget.popAfterMutations && context.mounted) Navigator.pop(context);
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Out for delivery'),
            ),
          ],
          if (widget.onCreateBilling != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () async => widget.onCreateBilling!(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Create billing'),
            ),
          ],
          const SizedBox(height: 10),
          PrintDocumentButton(
            onPrint: () => printDeliveryReceipt(context, widget.api, _delivery),
            label: 'Print PDF',
            enabled: !widget.offline,
          ),
        ],
      ),
    );
  }
}
