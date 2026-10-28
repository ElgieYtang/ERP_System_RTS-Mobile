import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../navigation/mobile_modules.dart';
import '../navigation/transaction_detail_host.dart';
import '../navigation/transaction_navigation.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';
import 'gate_pass_page.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';
import '../widgets/transaction_workflows.dart';

class OutslipsPage extends StatefulWidget {
  const OutslipsPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<OutslipsPage> createState() => _OutslipsPageState();
}

class _OutslipsPageState extends State<OutslipsPage> {
  bool _loading = true;
  bool _creating = false;
  bool _fromCache = false;
  String? _busyId;
  String? _error;
  String? _offlineLabel;
  String _filter = 'action';
  List<Map<String, dynamic>> _rows = [];
  TransactionLists _lists = const TransactionLists();

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'action':
        return _rows
            .where((r) => r['status'] == 'pending' || r['status'] == 'approved')
            .toList();
      case 'dispatch':
        return _rows.where((r) => r['status'] == 'for_dispatch').toList();
      case 'dr_ready':
        return _rows.where((r) {
          if (!isOutslipReadyForDr(r['status']?.toString())) return false;
          if (!_lists.crossModuleRulesReliable) return true;
          return !hasDrForOutslip(r, _lists);
        }).toList();
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
        widget.api.getList('/outslips'),
        TransactionLists.load(widget.api),
      ]);
      final data = results[0] as List<dynamic>;
      final lists = results[1] as TransactionLists;
      await OfflineCache.saveList(OfflineCache.outslips, data);
      if (!mounted) return;
      setState(() {
        _rows = data.cast<Map<String, dynamic>>();
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      final cached = await OfflineCache.loadList(OfflineCache.outslips);
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

    final id = row['dbId']?.toString() ?? row['id']?.toString();
    if (id == null || _busyId != null) return;
    if (!canApproveOutslipForUser(row, context.read<AuthState>().user)) return;

    setState(() => _busyId = id);
    try {
      final updated = await approveOutslip(context, widget.api, row);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _dispatch(Map<String, dynamic> row) async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }

    final id = row['dbId']?.toString() ?? row['id']?.toString();
    if (id == null || _busyId != null) return;
    if (!canDispatchOutslipForUser(row, context.read<AuthState>().user)) return;

    setState(() => _busyId = id);
    try {
      final updated = await dispatchOutslip(context, widget.api, row);
      if (updated != null) await _afterMutation(updated);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _createDeliveryReceipt(Map<String, dynamic> row, {bool popCurrentRoute = false}) async {
    if (_fromCache) {
    fieldShowOfflineBlocked(context);
      return;
    }
    final id = fieldDbId(row);
    if (id.isEmpty || _busyId != null) return;
    if (!canCreateDrFromOutslip(row, _lists)) return;
    setState(() => _busyId = id);
    try {
      final created = await confirmCreateDeliveryReceipt(context, widget.api, row);
      if (created != null) {
        await _afterMutation(null);
        if (!mounted) return;
        await openCreatedTransaction(
          context,
          widget.api,
          MobileModule.deliveries,
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
      final created = await showCreateOutslipDialog(context, widget.api, lists: _lists);
      if (created != null) {
        await _load();
        if (!mounted) return;
        await openCreatedTransaction(
          context,
          widget.api,
          MobileModule.outslips,
          created,
          offline: _fromCache,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _visible;
    final authUser = context.watch<AuthState>().user;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating || _fromCache ? null : _openCreate,
        icon: const Icon(Icons.add),
        label: Text(_creating ? 'Opening…' : 'New'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
          FieldFilterBar(
            value: _filter,
            options: const [
              (id: 'action', label: 'Needs action'),
              (id: 'dispatch', label: 'For dispatch'),
              (id: 'dr_ready', label: 'Ready for DR'),
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
              icon: Icons.outbox_outlined,
              title: _filter == 'action'
                  ? 'No outslips needing action'
                  : _filter == 'dr_ready'
                      ? 'No outslips ready for DR'
                      : 'No outslips',
              subtitle: _filter == 'dr_ready'
                  ? 'Only dispatched outslips without a delivery receipt appear here. '
                      'After you tap Create DR, open Deliveries from the home screen to work on the new DR.'
                  : _filter == 'dispatch'
                      ? 'Approve an outslip under Needs action, then mark it for dispatch.'
                      : null,
            ),
          ...visible.map((row) {
            final id = row['dbId']?.toString() ?? row['id']?.toString() ?? '';
            final status = row['status']?.toString() ?? '';
            final itemCount = (row['items'] as List<dynamic>? ?? const []).length;
            final busy = _busyId == id;
            final showApprove = canApproveOutslipForUser(row, authUser);
            final showDispatch = canDispatchOutslipForUser(row, authUser);
            final showCreateDr =
                _lists.crossModuleRulesReliable && canCreateDrFromOutslip(row, _lists);

            return Card(
              child: InkWell(
                onTap: () async {
                  await pushTransactionDetail(
                    context,
                    widget.api,
                    MobileModule.outslips,
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
                              row['id']?.toString() ?? 'OS',
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
                        'RCV: ${row['receivingId'] ?? '—'} · '
                        '$itemCount item(s)',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (showApprove)
                            FilledButton(
                              onPressed: busy || _fromCache ? null : () => _approve(row),
                              child: Text(busy ? '…' : 'Approve'),
                            ),
                          if (showDispatch)
                            FilledButton(
                              onPressed: busy || _fromCache ? null : () => _dispatch(row),
                              child: Text(busy ? '…' : 'Dispatch'),
                            ),
                          if (showCreateDr)
                            FilledButton(
                              onPressed: busy || _fromCache ? null : () => _createDeliveryReceipt(row),
                              child: Text(busy ? 'Working…' : 'Create DR'),
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

class OutslipDetailPage extends StatelessWidget {
  const OutslipDetailPage({
    super.key,
    required this.api,
    required this.outslip,
    this.offline = false,
    this.popAfterMutations = true,
    this.onApprove,
    this.onDispatch,
    this.onCreateDr,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
  });

  final ApiClient api;
  final Map<String, dynamic> outslip;
  final bool offline;
  final bool popAfterMutations;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onDispatch;
  final Future<void> Function()? onCreateDr;
  final String? workflowNotice;
  final bool workflowNoticeLoading;

  @override
  Widget build(BuildContext context) {
    final status = outslip['status']?.toString() ?? '';
    final items = (outslip['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final customer = outslip['customerName']?.toString().isNotEmpty == true
        ? outslip['customerName'].toString()
        : 'Customer —';

    return FieldDetailScaffold(
      title: outslip['id']?.toString() ?? 'Outslip',
      subtitle: customer,
      status: status,
      workflowNotice: workflowNotice,
      workflowNoticeLoading: workflowNoticeLoading,
      secondaryActions: [
        if (canPrintGatePass(outslip))
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GatePassPage(
                    api: api,
                    outslip: outslip,
                    offline: offline,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined, color: AppTheme.maroon),
            label: const Text('Gate pass'),
          ),
        PrintDocumentButton(
          onPrint: () => printOutslip(api, outslip),
          label: 'Outslip PDF',
        ),
      ],
      primaryActions: [
        if (onApprove != null)
          FilledButton(
            onPressed: () async {
              await onApprove!();
              if (popAfterMutations && context.mounted) Navigator.pop(context);
            },
            child: const Text('Approve outslip'),
          ),
        if (onDispatch != null)
          FilledButton(
            onPressed: () async {
              await onDispatch!();
              if (popAfterMutations && context.mounted) Navigator.pop(context);
            },
            child: const Text('Mark for dispatch'),
          ),
        if (onCreateDr != null)
          FilledButton.tonal(
            onPressed: () async => onCreateDr!(),
            child: const Text('Create delivery receipt'),
          ),
      ],
      children: [
        FieldDetailMeta(
          rows: [
            (label: 'Date', value: '${outslip['displayDate'] ?? outslip['date'] ?? '—'}'),
            (label: 'Receiving', value: '${outslip['receivingId'] ?? '—'}'),
          ],
        ),
        const SizedBox(height: 16),
        const FieldSectionTitle('Line items'),
        FieldLineItems(items: items),
      ],
    );
  }
}
