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
import '../widgets/transaction_workflows.dart';

class ReceivingsPage extends StatefulWidget {
  const ReceivingsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ReceivingsPage> createState() => _ReceivingsPageState();
}

class _ReceivingsPageState extends State<ReceivingsPage> {
  bool _loading = true;
  bool _fromCache = false;
  String? _busyId;
  String? _error;
  String? _offlineLabel;
  String _filter = 'open';
  List<Map<String, dynamic>> _rows = [];
  TransactionLists _lists = const TransactionLists();

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'open':
        return _rows.where((r) => r['status'] != 'completed').toList();
      case 'completed':
        return _rows.where((r) => r['status'] == 'completed').toList();
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
        widget.api.getList('/receivings'),
        TransactionLists.load(widget.api),
      ]);
      final data = results[0] as List<dynamic>;
      final lists = results[1] as TransactionLists;
      await OfflineCache.saveList(OfflineCache.receivings, data);
      if (!mounted) return;
      setState(() {
        _rows = data.cast<Map<String, dynamic>>();
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.receivings);
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

  Future<void> _confirm(Map<String, dynamic> row) async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }

    final id = row['dbId']?.toString() ?? row['id']?.toString();
    if (id == null || _busyId != null) return;
    if (!canConfirmReceiving(row)) return;

    setState(() => _busyId = id);
    try {
      final updated = await confirmReceiving(context, widget.api, row);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _createOutslip(Map<String, dynamic> row, {bool popCurrentRoute = false}) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    if (!canCreateOutslipFromReceivingSafe(row, _lists)) return;

    final created = await createOutslipFromReceiving(context, widget.api, row);
    if (created != null) {
      await _load();
      if (!mounted) return;
      await openCreatedTransaction(
        context,
        widget.api,
        MobileModule.outslips,
        created,
        popCurrentRoute: popCurrentRoute,
        offline: _fromCache,
      );
    }
  }

  Future<void> _viewOutslip(Map<String, dynamic> outslip) async {
    await pushTransactionDetail(
      context,
      widget.api,
      MobileModule.outslips,
      outslip,
      offline: _fromCache,
    );
    await _load();
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
              (id: 'open', label: 'Open'),
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
            FieldEmptyState(
              icon: Icons.inventory_2_outlined,
              title: _filter == 'open' ? 'No open receivings' : 'No receivings',
            ),
          ...visible.map((row) {
            final id = row['dbId']?.toString() ?? row['id']?.toString() ?? '';
            final status = row['status']?.toString() ?? '';
            final pending = canConfirmReceiving(row);
            final canCreateOutslip = canCreateOutslipFromReceivingSafe(row, _lists);
            final existingOutslip = findOutslipForReceiving(row, _lists);
            final itemCount = (row['items'] as List<dynamic>? ?? const []).length;
            final busy = _busyId == id;

            return Card(
              child: InkWell(
                onTap: () async {
                  await pushTransactionDetail(
                    context,
                    widget.api,
                    MobileModule.receiving,
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
                              row['id']?.toString() ?? 'Receiving',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          if (!pending && !canCreateOutslip && existingOutslip == null)
                            FieldStatusChip(status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${row['supplierName']?.toString().isNotEmpty == true ? row['supplierName'] : '—'} · '
                        '${row['displayDate'] ?? row['date'] ?? '—'}',
                      ),
                      Text('PO: ${row['purchaseOrderId'] ?? '—'} · $itemCount item(s)'),
                      if (pending || canCreateOutslip || existingOutslip != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (pending)
                              FilledButton(
                                onPressed: busy || _fromCache ? null : () => _confirm(row),
                                child: Text(busy ? '…' : 'Confirm'),
                              )
                            else if (canCreateOutslip)
                              FilledButton.tonal(
                                onPressed: _fromCache ? null : () => _createOutslip(row),
                                child: const Text('Create outslip'),
                              )
                            else if (existingOutslip != null && _lists.crossModuleRulesReliable)
                              OutlinedButton(
                                onPressed: () => _viewOutslip(existingOutslip),
                                child: const Text('View outslip'),
                              ),
                          ],
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

class ReceivingDetailPage extends StatelessWidget {
  const ReceivingDetailPage({
    super.key,
    required this.receivingId,
    required this.initial,
    this.popAfterMutations = true,
    this.onConfirm,
    this.onCreateOutslip,
    this.onViewOutslip,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
  });

  final String receivingId;
  final Map<String, dynamic> initial;
  final bool popAfterMutations;
  final Future<void> Function()? onConfirm;
  final Future<void> Function()? onCreateOutslip;
  final Future<void> Function()? onViewOutslip;
  final String? workflowNotice;
  final bool workflowNoticeLoading;

  @override
  Widget build(BuildContext context) {
    final items = (initial['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final pending = canConfirmReceiving(initial);
    final completed = initial['status']?.toString() == 'completed';
    final missingCustomer = completed && !receivingHasQuotationCustomer(initial);
    final supplier = initial['supplierName']?.toString().isNotEmpty == true
        ? initial['supplierName'].toString()
        : 'Supplier —';

    return FieldDetailScaffold(
      title: initial['id']?.toString() ?? 'Receiving',
      subtitle: supplier,
      status: initial['status']?.toString(),
      workflowNotice: workflowNotice,
      workflowNoticeLoading: workflowNoticeLoading,
      primaryActions: [
        if (pending && onConfirm != null)
          FilledButton(
            onPressed: () async {
              await onConfirm!();
              if (popAfterMutations && context.mounted) Navigator.pop(context);
            },
            child: const Text('Confirm receiving'),
          ),
        if (!pending && onCreateOutslip != null)
          FilledButton.tonal(
            onPressed: () async => onCreateOutslip!(),
            child: const Text('Create outslip'),
          ),
        if (!pending && onViewOutslip != null)
          OutlinedButton(
            onPressed: () async => onViewOutslip!(),
            child: const Text('View outslip'),
          ),
        if (missingCustomer)
          const Text(
            'Outslip requires a quotation customer on this receiving.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
      ],
      secondaryActions: [
        PrintDocumentButton(
          onPrint: () => printReceiving(initial),
          label: 'Print PDF',
        ),
      ],
      children: [
        FieldDetailMeta(
          rows: [
            (label: 'Date', value: '${initial['displayDate'] ?? initial['date'] ?? '—'}'),
            (label: 'PO', value: '${initial['purchaseOrderId'] ?? '—'}'),
          ],
        ),
        if ((initial['remarks']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            initial['remarks'].toString(),
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        const FieldSectionTitle('Line items'),
        FieldLineItems(items: items),
      ],
    );
  }
}
