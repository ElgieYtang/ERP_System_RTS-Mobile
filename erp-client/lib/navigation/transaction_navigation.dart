import 'package:flutter/material.dart';

import '../navigation/mobile_modules.dart';
import '../screens/billing_page.dart';
import '../screens/deliveries_page.dart';
import '../screens/outslips_page.dart';
import '../screens/purchase_orders_page.dart';
import '../screens/quotations_page.dart';
import '../screens/receivings_page.dart';
import '../services/api_client.dart';
import '../services/transaction_actions.dart';
import 'transaction_detail_host.dart';

Map<String, dynamic>? recordFromPayload(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return null;
}

bool sameTransactionRow(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aDb = a['dbId']?.toString() ?? '';
  final bDb = b['dbId']?.toString() ?? '';
  if (aDb.isNotEmpty && bDb.isNotEmpty) return aDb == bDb;
  final aId = a['id']?.toString() ?? '';
  final bId = b['id']?.toString() ?? '';
  return aId.isNotEmpty && aId == bId;
}

Map<String, dynamic> mergeRecordFromMutation(
  Map<String, dynamic> source,
  Map<String, dynamic> response, {
  Map<String, dynamic>? fallbackPatch,
}) {
  final patch = recordFromPayload(response);
  if (patch != null) {
    return Map<String, dynamic>.from({...source, ...patch});
  }
  if (fallbackPatch != null) {
    return Map<String, dynamic>.from({...source, ...fallbackPatch});
  }
  return Map<String, dynamic>.from(source);
}

String? transactionListPathForModule(MobileModule module) {
  switch (module) {
    case MobileModule.quotations:
      return '/quotations';
    case MobileModule.purchaseOrders:
      return '/purchase-orders';
    case MobileModule.receiving:
      return '/receivings';
    case MobileModule.outslips:
      return '/outslips';
    case MobileModule.deliveries:
      return '/delivery-receipts';
    case MobileModule.billing:
      return '/billings';
    default:
      return null;
  }
}

bool transactionRecordHasDetails(MobileModule module, Map<String, dynamic> record) {
  final items = record['items'];
  if (items is List && items.isNotEmpty) return true;
  if (module == MobileModule.billing) {
    return record['amount'] != null || record['total'] != null;
  }
  return false;
}

String? transactionDetailPath(MobileModule module, Map<String, dynamic> record) {
  final ref = record['dbId']?.toString().trim();
  final docId = record['id']?.toString().trim();
  final id = (ref != null && ref.isNotEmpty) ? ref : docId;
  if (id == null || id.isEmpty) return null;

  switch (module) {
    case MobileModule.deliveries:
      return '/delivery-receipts/${Uri.encodeComponent(id)}';
    case MobileModule.outslips:
      return '/outslips/${Uri.encodeComponent(id)}';
    default:
      return null;
  }
}

/// Load a single transaction row when the list payload is missing line items or totals.
Future<Map<String, dynamic>> resolveTransactionDetailRecord(
  ApiClient api,
  MobileModule module,
  Map<String, dynamic> record,
) async {
  final needsRefresh = module == MobileModule.deliveries
      ? deliveryRecordNeedsDetailRefresh(record)
      : !transactionRecordHasDetails(module, record);
  if (!needsRefresh) return record;

  if (module == MobileModule.deliveries) {
    try {
      return await fetchDeliveryDetailRecord(api, record);
    } catch (_) {
      return resolveCreatedTransactionRecord(api, module, record);
    }
  }

  final path = transactionDetailPath(module, record);
  if (path != null) {
    try {
      final response = await api.request('GET', path);
      if (response is Map) {
        final data = recordFromPayload(Map<String, dynamic>.from(response));
        if (data != null) {
          return Map<String, dynamic>.from({...record, ...data});
        }
      }
    } catch (_) {}
  }

  return resolveCreatedTransactionRecord(api, module, record);
}

/// After create/convert, API should return a full row; if not, load from the list endpoint.
Future<Map<String, dynamic>> resolveCreatedTransactionRecord(
  ApiClient api,
  MobileModule module,
  Map<String, dynamic> record,
) async {
  if (transactionRecordHasDetails(module, record)) return record;

  final path = transactionListPathForModule(module);
  if (path == null) return record;

  final dbId = record['dbId']?.toString();
  final docId = record['id']?.toString();
  try {
    final rows = (await api.getList(path)).cast<Map<String, dynamic>>();
    for (final row in rows) {
      if (dbId != null && dbId.isNotEmpty && row['dbId']?.toString() == dbId) {
        return Map<String, dynamic>.from(row);
      }
      if (docId != null && docId.isNotEmpty && row['id']?.toString() == docId) {
        return Map<String, dynamic>.from(row);
      }
    }
  } catch (_) {}

  return record;
}

List<Map<String, dynamic>> upsertTransactionRow(
  List<Map<String, dynamic>> rows,
  Map<String, dynamic> updated,
) {
  var found = false;
  final next = rows.map((row) {
    if (sameTransactionRow(row, updated)) {
      found = true;
      return Map<String, dynamic>.from({...row, ...updated});
    }
    return row;
  }).toList();
  if (!found) {
    next.insert(0, Map<String, dynamic>.from(updated));
  }
  return next;
}

/// Opens a transaction detail screen with full workflow actions.
Future<void> openCreatedTransaction(
  BuildContext context,
  ApiClient api,
  MobileModule module,
  Map<String, dynamic> record, {
  bool popCurrentRoute = false,
  bool offline = false,
}) async {
  if (!context.mounted) return;
  if (popCurrentRoute && Navigator.canPop(context)) {
    Navigator.pop(context);
  }
  if (!context.mounted) return;

  final resolved = await resolveTransactionDetailRecord(api, module, record);
  if (!context.mounted) return;

  await pushTransactionDetail(context, api, module, resolved, offline: offline);
}

Widget buildTransactionDetailPage({
  required ApiClient api,
  required MobileModule module,
  required Map<String, dynamic> record,
  bool popAfterMutations = true,
  bool offline = false,
  bool canReceive = false,
  Future<void> Function()? onReceive,
  Future<void> Function()? onConfirm,
  Future<void> Function()? onCreateOutslip,
  Future<void> Function()? onViewOutslip,
  Future<void> Function()? onApprove,
  Future<void> Function()? onDispatch,
  Future<void> Function()? onCreateDr,
  Future<void> Function(String status)? onSetStatus,
  Future<void> Function()? onCreateBilling,
  ValueChanged<Map<String, dynamic>>? onDeliveryUpdated,
  Future<void> Function()? onApproveQuotation,
  Future<void> Function()? onConvert,
  Future<void> Function()? onCancel,
  Future<void> Function()? onEdit,
  String? workflowNotice,
  bool workflowNoticeLoading = false,
}) {
  switch (module) {
    case MobileModule.purchaseOrders:
      return PurchaseOrderDetailPage(
        api: api,
        order: record,
        canReceive: canReceive,
        onReceive: onReceive,
        offline: offline,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    case MobileModule.receiving:
      return ReceivingDetailPage(
        receivingId: record['dbId']?.toString() ?? record['id']?.toString() ?? '',
        initial: record,
        popAfterMutations: popAfterMutations,
        onConfirm: onConfirm,
        onCreateOutslip: onCreateOutslip,
        onViewOutslip: onViewOutslip,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    case MobileModule.outslips:
      return OutslipDetailPage(
        api: api,
        outslip: record,
        offline: offline,
        popAfterMutations: popAfterMutations,
        onApprove: onApprove,
        onDispatch: onDispatch,
        onCreateDr: onCreateDr,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    case MobileModule.deliveries:
      return DeliveryDetailPage(
        api: api,
        delivery: record,
        popAfterMutations: popAfterMutations,
        onSetStatus: onSetStatus,
        onCreateBilling: onCreateBilling,
        onDeliveryUpdated: onDeliveryUpdated,
        offline: offline,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    case MobileModule.billing:
      return BillingDetailPage(
        billing: record,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    case MobileModule.quotations:
      return QuotationDetailPage(
        api: api,
        quotation: record,
        popAfterMutations: popAfterMutations,
        onApprove: onApproveQuotation,
        onConvert: onConvert,
        onCancel: onCancel,
        onEdit: onEdit,
        offline: offline,
        workflowNotice: workflowNotice,
        workflowNoticeLoading: workflowNoticeLoading,
      );
    default:
      return Scaffold(
        appBar: AppBar(title: Text(record['id']?.toString() ?? 'Record')),
        body: Center(child: Text('${record['id'] ?? 'Record'} created.')),
      );
  }
}
