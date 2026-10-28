import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/mobile_modules.dart';
import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import '../state/auth_state.dart';
import '../navigation/module_navigation_scope.dart';
import 'transaction_navigation.dart';
import '../widgets/field_ui.dart';
import '../widgets/transaction_workflows.dart';

String? transactionDetailWorkflowNotice({
  required bool loadingLists,
  required bool offline,
  required bool crossModuleRulesReliable,
}) {
  if (loadingLists) return 'Checking linked records…';
  if (offline) return 'Offline — reconnect to update this record.';
  if (!crossModuleRulesReliable) return partialCacheWorkflowMessage;
  return null;
}

/// Detail screen with live workflow buttons — used for list open and post-create navigation.
class TransactionDetailHost extends StatefulWidget {
  const TransactionDetailHost({
    super.key,
    required this.api,
    required this.module,
    required this.initialRecord,
    this.offline = false,
  });

  final ApiClient api;
  final MobileModule module;
  final Map<String, dynamic> initialRecord;
  final bool offline;

  @override
  State<TransactionDetailHost> createState() => _TransactionDetailHostState();
}

class _TransactionDetailHostState extends State<TransactionDetailHost> {
  late Map<String, dynamic> _record;
  TransactionLists _lists = const TransactionLists(crossModuleRulesReliable: false);
  bool _loadingLists = true;
  bool _busy = false;

  bool get _listsReady => !_loadingLists;

  @override
  void initState() {
    super.initState();
    _record = Map<String, dynamic>.from(widget.initialRecord);
    _loadLists();
    _refreshDetailIfNeeded();
  }

  Future<void> _refreshDetailIfNeeded() async {
    if (widget.offline) return;
    final needs = widget.module == MobileModule.deliveries
        ? deliveryRecordNeedsDetailRefresh(_record)
        : !transactionRecordHasDetails(widget.module, _record);
    if (!needs) return;

    try {
      final resolved = await resolveTransactionDetailRecord(
        widget.api,
        widget.module,
        _record,
      );
      if (!mounted) return;
      setState(() => _record = resolved);
    } catch (_) {}
  }

  Future<void> _loadLists() async {
    setState(() => _loadingLists = true);
    try {
      final lists = await TransactionLists.load(widget.api);
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loadingLists = false;
      });
    } catch (error) {
      final lists = await TransactionLists.fromCache();
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loadingLists = false;
      });
      if (!lists.crossModuleRulesReliable && !widget.offline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline — some workflow actions may be hidden until you reconnect.'),
          ),
        );
      } else if (lists.crossModuleRulesReliable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }

  Future<void> _handoff(MobileModule module, Map<String, dynamic> record) async {
    if (!mounted) return;
    final resolved = await resolveCreatedTransactionRecord(widget.api, module, record);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => wrapModuleNavigationScope(
          context,
          TransactionDetailHost(
            api: widget.api,
            module: module,
            initialRecord: resolved,
            offline: widget.offline,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshRecord(Map<String, dynamic> record) async {
    if (!mounted) return;
    setState(() => _record = Map<String, dynamic>.from({..._record, ...record}));
    await _loadLists();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthState>().user;

    return buildTransactionDetailPage(
      api: widget.api,
      module: widget.module,
      record: _record,
      popAfterMutations: false,
      offline: widget.offline,
      workflowNotice: transactionDetailWorkflowNotice(
        loadingLists: _loadingLists,
        offline: widget.offline,
        crossModuleRulesReliable: _lists.crossModuleRulesReliable,
      ),
      workflowNoticeLoading: _loadingLists,
      canReceive: !widget.offline &&
          _listsReady &&
          _lists.crossModuleRulesReliable &&
          widget.module == MobileModule.purchaseOrders &&
          canReceivePurchaseOrder(_record, _lists),
      onReceive: !widget.offline &&
              _listsReady &&
              _lists.crossModuleRulesReliable &&
              widget.module == MobileModule.purchaseOrders &&
              canReceivePurchaseOrder(_record, _lists)
          ? () => _run(() async {
                final next = await receivePurchaseOrder(
                  context,
                  widget.api,
                  _record,
                  _lists,
                );
                if (next != null) await _handoff(MobileModule.receiving, next);
              })
          : null,
      onConfirm: !widget.offline &&
              widget.module == MobileModule.receiving &&
              canConfirmReceiving(_record)
          ? () => _run(() async {
                final updated = await confirmReceiving(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onCreateOutslip: !widget.offline &&
              _listsReady &&
              widget.module == MobileModule.receiving &&
              canCreateOutslipFromReceivingSafe(_record, _lists)
          ? () => _run(() async {
                final next = await createOutslipFromReceiving(
                  context,
                  widget.api,
                  _record,
                );
                if (next != null) await _handoff(MobileModule.outslips, next);
              })
          : null,
      onViewOutslip: _listsReady &&
              widget.module == MobileModule.receiving &&
              _lists.crossModuleRulesReliable &&
              findOutslipForReceiving(_record, _lists) != null
          ? () => _run(() async {
                final outslip = findOutslipForReceiving(_record, _lists);
                if (outslip != null) await _handoff(MobileModule.outslips, outslip);
              })
          : null,
      onApprove: !widget.offline &&
              canApproveOutslipForUser(_record, authUser)
          ? () => _run(() async {
                final updated = await approveOutslip(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onDispatch: !widget.offline &&
              canDispatchOutslipForUser(_record, authUser)
          ? () => _run(() async {
                final updated = await dispatchOutslip(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onCreateDr: !widget.offline &&
              _listsReady &&
              widget.module == MobileModule.outslips &&
              _lists.crossModuleRulesReliable &&
              canCreateDrFromOutslip(_record, _lists)
          ? () => _run(() async {
                final next = await confirmCreateDeliveryReceipt(
                  context,
                  widget.api,
                  _record,
                );
                if (next != null) await _handoff(MobileModule.deliveries, next);
              })
          : null,
      onSetStatus: !widget.offline &&
              widget.module == MobileModule.deliveries &&
              (canMarkDeliveryOut(_record) || canMarkDeliveryDelivered(_record))
          ? (status) => _run(() async {
                final updated = await updateDeliveryStatus(
                  context,
                  widget.api,
                  _record,
                  status,
                );
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onDeliveryUpdated: !widget.offline && widget.module == MobileModule.deliveries
          ? (updated) => _refreshRecord(updated)
          : null,
      onCreateBilling: !widget.offline &&
              _listsReady &&
              _lists.crossModuleRulesReliable &&
              widget.module == MobileModule.deliveries &&
              canCreateBillingFromDelivery(_record, _lists)
          ? () => _run(() async {
                final next = await confirmCreateBilling(context, widget.api, _record);
                if (next != null) await _handoff(MobileModule.billing, next);
              })
          : null,
      onApproveQuotation: !widget.offline &&
              widget.module == MobileModule.quotations &&
              canApproveQuotation(_record)
          ? () => _run(() async {
                final updated = await approveQuotation(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onConvert: !widget.offline &&
              _listsReady &&
              _lists.crossModuleRulesReliable &&
              widget.module == MobileModule.quotations &&
              canConvertQuotation(_record, _lists)
          ? () => _run(() async {
                final next = await convertQuotationToPo(context, widget.api, _record);
                if (next != null) await _handoff(MobileModule.purchaseOrders, next);
              })
          : null,
      onCancel: !widget.offline &&
              _listsReady &&
              _lists.crossModuleRulesReliable &&
              widget.module == MobileModule.quotations &&
              canCancelQuotation(_record, _lists)
          ? () => _run(() async {
                final updated = await cancelQuotation(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
      onEdit: !widget.offline &&
              _listsReady &&
              _lists.crossModuleRulesReliable &&
              widget.module == MobileModule.quotations &&
              canEditQuotation(_record, _lists)
          ? () => _run(() async {
                final updated = await editQuotation(context, widget.api, _record);
                if (updated != null) await _refreshRecord(updated);
              })
          : null,
    );
  }
}

Future<void> pushTransactionDetail(
  BuildContext context,
  ApiClient api,
  MobileModule module,
  Map<String, dynamic> record, {
  bool offline = false,
}) async {
  final initial = offline
      ? record
      : await resolveTransactionDetailRecord(api, module, record);
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => wrapModuleNavigationScope(
        context,
        TransactionDetailHost(
          api: api,
          module: module,
          initialRecord: initial,
          offline: offline,
        ),
      ),
    ),
  );
}
