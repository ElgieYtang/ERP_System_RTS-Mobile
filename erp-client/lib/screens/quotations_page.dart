import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import '../navigation/mobile_modules.dart';
import '../navigation/module_navigation_scope.dart';
import '../navigation/transaction_detail_host.dart';
import '../navigation/transaction_navigation.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';
import '../widgets/transaction_workflows.dart';
import 'add_quotation_page.dart';

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  bool _loading = true;
  bool _creating = false;
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
        return _rows.where((r) => r['status'] == 'pending').toList();
      case 'approved':
        return _rows.where((r) => r['status'] == 'approved').toList();
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
        widget.api.getList('/quotations'),
        TransactionLists.load(widget.api),
      ]);
      final data = results[0] as List<dynamic>;
      final lists = results[1] as TransactionLists;
      await OfflineCache.saveList(OfflineCache.quotations, data);
      if (!mounted) return;
      setState(() {
        _rows = data.cast<Map<String, dynamic>>();
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.quotations);
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

  Future<void> _approve(Map<String, dynamic> row) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldRowId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canApproveQuotation(row)) return;

    setState(() => _busyId = id);
    try {
      final updated = await approveQuotation(context, widget.api, row);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldRowId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canCancelQuotation(row, _lists)) return;

    setState(() => _busyId = id);
    try {
      final updated = await cancelQuotation(context, widget.api, row);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _convertToPo(Map<String, dynamic> row, {bool popCurrentRoute = false}) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldRowId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canConvertQuotation(row, _lists)) return;

    setState(() => _busyId = id);
    try {
      final created = await convertQuotationToPo(context, widget.api, row);
      if (created != null) {
        await _load();
        if (!mounted) return;
        await openCreatedTransaction(
          context,
          widget.api,
          MobileModule.purchaseOrders,
          created,
          popCurrentRoute: popCurrentRoute,
          offline: _fromCache,
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openCreate() async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    if (_creating) return;

    setState(() => _creating = true);
    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => wrapModuleNavigationScope(
            context,
            AddQuotationPage(api: widget.api),
          ),
        ),
      );
      if (created == true) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _creating = false);
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating || _fromCache ? null : _openCreate,
        icon: const Icon(Icons.add),
        label: Text(_creating ? 'Opening…' : 'New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.maroon,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
          FieldFilterBar(
            value: _filter,
            options: const [
              (id: 'action', label: 'Pending'),
              (id: 'approved', label: 'Approved'),
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
              icon: Icons.request_quote_outlined,
              title: _rows.isEmpty
                  ? 'No quotations'
                  : 'No ${_filter == 'approved' ? 'approved' : 'pending'} quotations',
              subtitle: _rows.isNotEmpty && _filter != 'all'
                  ? 'Try the All tab to see every quotation.'
                  : null,
            ),
          ...visible.map((row) {
            final id = fieldRowId(row);
            final status = row['status']?.toString() ?? '';
            final busy = _busyId == id;
            final items = (row['items'] as List<dynamic>? ?? const []).length;
            final showApprove = canApproveQuotation(row);
            final showCancel = _lists.crossModuleRulesReliable && canCancelQuotation(row, _lists);
            final showConvert = _lists.crossModuleRulesReliable && canConvertQuotation(row, _lists);

            return Card(
              child: InkWell(
                onTap: () => pushTransactionDetail(
                  context,
                  widget.api,
                  MobileModule.quotations,
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
                              row['id']?.toString() ?? 'QTN',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          FieldStatusChip(status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(row['customerName']?.toString() ?? 'Customer —'),
                      Text(
                        '${row['displayDate'] ?? row['date'] ?? '—'} · '
                        '${fieldFormatMoney(row['total'])} · $items item(s)',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (showApprove)
                            FilledButton(
                              onPressed: busy || _fromCache ? null : () => _approve(row),
                              child: Text(busy ? 'Working…' : 'Approve'),
                            ),
                          if (showCancel)
                            OutlinedButton(
                              onPressed: busy || _fromCache ? null : () => _cancel(row),
                              child: const Text('Cancel'),
                            ),
                          if (showConvert)
                            FilledButton.tonal(
                              onPressed: busy || _fromCache ? null : () => _convertToPo(row),
                              child: const Text('Convert to PO'),
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
      ),
    );
  }
}

class QuotationDetailPage extends StatelessWidget {
  const QuotationDetailPage({
    super.key,
    required this.api,
    required this.quotation,
    this.popAfterMutations = true,
    this.onApprove,
    this.onConvert,
    this.onCancel,
    this.onEdit,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
    this.offline = false,
  });

  final ApiClient api;
  final Map<String, dynamic> quotation;
  final bool popAfterMutations;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onConvert;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onEdit;
  final String? workflowNotice;
  final bool workflowNoticeLoading;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final items = (quotation['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return FieldDetailScaffold(
      title: quotation['id']?.toString() ?? 'Quotation',
      subtitle: quotation['customerName']?.toString() ?? 'Customer —',
      status: quotation['status']?.toString(),
      workflowNotice: workflowNotice,
      workflowNoticeLoading: workflowNoticeLoading,
      secondaryActions: [
        if (onEdit != null)
          OutlinedButton.icon(
            onPressed: () async => onEdit!(),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        PrintDocumentButton(
          onPrint: () => printQuotation(context, api, quotation),
          label: 'Print PDF',
          enabled: !offline,
        ),
      ],
      primaryActions: [
        if (onApprove != null)
          FilledButton(
            onPressed: () async {
              await onApprove!();
              if (popAfterMutations && context.mounted) Navigator.pop(context);
            },
            child: const Text('Approve'),
          ),
        if (onConvert != null)
          FilledButton.tonal(
            onPressed: () async => onConvert!(),
            child: const Text('Convert to PO'),
          ),
        if (onCancel != null)
          OutlinedButton(
            onPressed: () async {
              await onCancel!();
              if (popAfterMutations && context.mounted) Navigator.pop(context);
            },
            child: const Text('Cancel quotation'),
          ),
      ],
      children: [
        FieldDetailMeta(
          rows: [
            (
              label: 'Date',
              value: '${quotation['displayDate'] ?? quotation['date'] ?? '—'}',
            ),
            (label: 'Total', value: fieldFormatMoney(quotation['total'])),
          ],
        ),
        const SizedBox(height: 16),
        const FieldSectionTitle('Line items'),
        FieldLineItems(items: items),
      ],
    );
  }
}
