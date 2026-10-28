import '../widgets/field_ui.dart';
import 'api_client.dart';
import 'offline_cache.dart';
import 'transaction_lists.dart';

bool _idsMatch(dynamic a, dynamic b) {
  if (a == null || b == null) return false;
  return a.toString() == b.toString();
}

String? _quotationPublicId(Map<String, dynamic> quotation) =>
    quotation['id']?.toString();

Map<String, dynamic>? findPoForQuotation(
  Map<String, dynamic> quotation,
  TransactionLists lists,
) {
  final qtnId = _quotationPublicId(quotation);
  final qtnDb = fieldDbId(quotation);
  for (final po in lists.purchaseOrders) {
    if (_idsMatch(po['referenceQuotationId'], qtnId) ||
        _idsMatch(po['referenceQuotationId'], qtnDb) ||
        _idsMatch(po['referenceQuotationNo'], qtnId)) {
      return po;
    }
  }
  return null;
}

bool canApproveQuotation(Map<String, dynamic> row) =>
    row['status']?.toString() == 'pending';

/// Cancel when not already cancelled and no PO has been created from this quotation.
bool canCancelQuotation(Map<String, dynamic> row, TransactionLists lists) {
  final status = row['status']?.toString() ?? '';
  if (status == 'cancelled') return false;
  return findPoForQuotation(row, lists) == null;
}

/// Edit date/status when not cancelled and no PO has been created yet.
bool canEditQuotation(Map<String, dynamic> row, TransactionLists lists) {
  final status = row['status']?.toString() ?? '';
  if (status == 'cancelled') return false;
  return findPoForQuotation(row, lists) == null;
}

bool canConvertQuotation(Map<String, dynamic> row, TransactionLists lists) =>
    row['status']?.toString() == 'approved' && findPoForQuotation(row, lists) == null;

bool hasReceivingForPo(Map<String, dynamic> po, TransactionLists lists) {
  final poDb = fieldDbId(po);
  final poNo = po['id']?.toString();
  return lists.receivings.any(
    (row) =>
        _idsMatch(row['purchaseOrderDbId'], poDb) || _idsMatch(row['purchaseOrderId'], poNo),
  );
}

Map<String, dynamic>? findReceivingForPo(Map<String, dynamic> po, TransactionLists lists) {
  final poDb = fieldDbId(po);
  final poNo = po['id']?.toString();
  for (final row in lists.receivings) {
    if (_idsMatch(row['purchaseOrderDbId'], poDb) || _idsMatch(row['purchaseOrderId'], poNo)) {
      return row;
    }
  }
  return null;
}

bool hasOpenReceivingForPo(Map<String, dynamic> po, TransactionLists lists) {
  final poDb = fieldDbId(po);
  final poNo = po['id']?.toString();
  return lists.receivings.any((row) {
    final open = row['status']?.toString() != 'completed';
    return open &&
        (_idsMatch(row['purchaseOrderDbId'], poDb) || _idsMatch(row['purchaseOrderId'], poNo));
  });
}

bool canReceivePurchaseOrder(Map<String, dynamic> po, TransactionLists lists) {
  final status = po['status']?.toString() ?? '';
  if (status == 'fully_received' || status == 'cancelled') return false;
  return !hasReceivingForPo(po, lists);
}

bool canConfirmReceiving(Map<String, dynamic> row) =>
    row['status']?.toString() != 'completed';

bool hasOutslipForReceiving(Map<String, dynamic> receiving, TransactionLists lists) {
  final rcvDb = fieldDbId(receiving);
  return lists.outslips.any((row) => _idsMatch(row['receivingId'], rcvDb));
}

Map<String, dynamic>? findOutslipForReceiving(
  Map<String, dynamic> receiving,
  TransactionLists lists,
) {
  final rcvDb = fieldDbId(receiving);
  for (final row in lists.outslips) {
    if (_idsMatch(row['receivingId'], rcvDb)) {
      return row;
    }
  }
  return null;
}

bool receivingHasQuotationCustomer(Map<String, dynamic> receiving) {
  final id = receiving['customerId']?.toString();
  return id != null && id.isNotEmpty;
}

bool canCreateOutslipFromReceiving(
  Map<String, dynamic> receiving,
  TransactionLists lists,
) =>
    receiving['status']?.toString() == 'completed' &&
    receivingHasQuotationCustomer(receiving) &&
    !hasOutslipForReceiving(receiving, lists);

bool canCreateOutslipFromReceivingSafe(
  Map<String, dynamic> receiving,
  TransactionLists lists,
) =>
    lists.crossModuleRulesReliable && canCreateOutslipFromReceiving(receiving, lists);

bool canApproveOutslip(Map<String, dynamic> row) => row['status']?.toString() == 'pending';

bool canDispatchOutslip(Map<String, dynamic> row) => row['status']?.toString() == 'approved';

bool userIsAdmin(Map<String, dynamic>? user) => user?['role']?.toString() == 'admin';

bool canApproveOutslipForUser(Map<String, dynamic> row, Map<String, dynamic>? user) =>
    canApproveOutslip(row) && userIsAdmin(user);

bool canDispatchOutslipForUser(Map<String, dynamic> row, Map<String, dynamic>? user) =>
    canDispatchOutslip(row) && userIsAdmin(user);

bool canPrintGatePass(Map<String, dynamic> row) {
  final status = row['status']?.toString() ?? '';
  return status == 'approved' || status == 'for_dispatch' || status == 'released';
}

bool isGatePassExited(Map<String, dynamic> document) =>
    (document['status']?.toString() ?? '').toLowerCase() == 'exited';

bool canEditGatePass(Map<String, dynamic> document, {bool offline = false}) =>
    !offline && !isGatePassExited(document);

bool canMarkGatePassExited(Map<String, dynamic> document, {bool offline = false}) =>
    !offline && !isGatePassExited(document);

Map<String, dynamic> buildGatePassPayload({
  required String destination,
  required String driverName,
  required String plateNo,
  required String vehicleNo,
  required String remarks,
}) =>
    {
      'destination': destination.trim(),
      'driverName': driverName.trim(),
      'plateNo': plateNo.trim(),
      'vehicleNo': vehicleNo.trim(),
      'remarks': remarks.trim(),
    };

Map<String, dynamic> mergeGatePassDocument(
  Map<String, dynamic> document,
  Map<String, dynamic> payload,
) =>
    {
      ...document,
      ...payload,
    };

String gatePassEditBlockedMessage({bool offline = false}) => offline
    ? 'Offline — reconnect to save gate pass details.'
    : 'This gate pass can no longer be edited.';

String gatePassExitBlockedMessage({bool offline = false}) => offline
    ? 'Offline — reconnect to mark this gate pass as exited.'
    : 'This gate pass has already been marked as exited.';

bool isOutslipReadyForDr(String? status) {
  final value = (status ?? '').toLowerCase();
  return value == 'for_dispatch' || value == 'released';
}

bool hasDrForOutslip(Map<String, dynamic> outslip, TransactionLists lists) {
  final osDb = fieldDbId(outslip);
  final osNo = outslip['id']?.toString();
  return lists.deliveryReceipts.any(
    (row) =>
        _idsMatch(row['referenceOutslipDbId'], osDb) ||
        _idsMatch(row['referenceOutslipId'], osNo),
  );
}

bool canCreateDrFromOutslip(Map<String, dynamic> outslip, TransactionLists lists) =>
    isOutslipReadyForDr(outslip['status']?.toString()) && !hasDrForOutslip(outslip, lists);

List<Map<String, dynamic>> deliveryLineItems(Map<String, dynamic> delivery) {
  return (delivery['items'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

bool deliveryRecordNeedsDetailRefresh(Map<String, dynamic> record) {
  if (deliveryLineItems(record).isEmpty) return true;
  final total = (record['total'] as num?)?.toDouble();
  return total == null || total <= 0;
}

Map<String, dynamic>? _mergeDeliveryFromListRow(
  Map<String, dynamic> delivery,
  Iterable<Map<String, dynamic>> rows,
  Set<String> refs,
) {
  for (final row in rows) {
    final matches = refs.any(
      (ref) => row['dbId']?.toString() == ref || row['id']?.toString() == ref,
    );
    if (matches && deliveryLineItems(row).isNotEmpty) {
      return Map<String, dynamic>.from({...delivery, ...row});
    }
  }
  return null;
}

Map<String, dynamic>? _deliveryFromOutslipRow(
  Map<String, dynamic> delivery,
  Map<String, dynamic> os,
) {
  final osItems = deliveryLineItems(os);
  if (osItems.isEmpty) return null;
  final items = osItems
      .map(
        (item) => {
          ...item,
          'serialNumbers': (item['serialNumbers'] as List<dynamic>? ?? const [])
              .map((v) => v.toString())
              .toList(),
          'brandSerial': item['brandSerial']?.toString() ?? '',
        },
      )
      .toList();
  final total = (delivery['total'] as num?)?.toDouble() ??
      (os['total'] as num?)?.toDouble() ??
      items.fold<double>(
        0,
        (sum, line) => sum + ((line['amount'] as num?)?.toDouble() ?? 0),
      );
  return Map<String, dynamic>.from({
    ...delivery,
    'items': items,
    'total': total,
  });
}

Future<Map<String, dynamic>?> _deliveryFromOfflineCache(
  Map<String, dynamic> delivery,
  Set<String> refs,
) async {
  final deliveries = await OfflineCache.loadList(OfflineCache.deliveries);
  final fromDr = _mergeDeliveryFromListRow(delivery, deliveries.rows, refs);
  if (fromDr != null) return fromDr;

  final outslipRef =
      delivery['referenceOutslipDbId'] ?? delivery['referenceOutslipId'];
  if (outslipRef == null || outslipRef.toString().isEmpty) return null;

  final outslips = await OfflineCache.loadList(OfflineCache.outslips);
  for (final row in outslips.rows) {
    final matches = row['dbId']?.toString() == outslipRef.toString() ||
        row['id']?.toString() == outslipRef.toString();
    if (matches) {
      return _deliveryFromOutslipRow(delivery, row);
    }
  }
  return null;
}

/// Resolves a delivery row with line items (GET detail, list row, or outslip fallback).
Future<Map<String, dynamic>> fetchDeliveryDetailRecord(
  ApiClient api,
  Map<String, dynamic> delivery,
) async {
  final dbId = delivery['dbId']?.toString().trim();
  final docId = delivery['id']?.toString().trim();
  final refs = <String>{
    if (dbId != null && dbId.isNotEmpty) dbId,
    if (docId != null && docId.isNotEmpty) docId,
  };

  for (final ref in refs) {
    try {
      final data = await api.getData('/delivery-receipts/${Uri.encodeComponent(ref)}');
      if (deliveryLineItems(data).isNotEmpty) {
        return Map<String, dynamic>.from({...delivery, ...data});
      }
    } catch (_) {}
  }

  try {
    final rows = (await api.getList('/delivery-receipts')).cast<Map<String, dynamic>>();
    final merged = _mergeDeliveryFromListRow(delivery, rows, refs);
    if (merged != null) return merged;
  } catch (_) {}

  final outslipRef = delivery['referenceOutslipDbId'] ?? delivery['referenceOutslipId'];
  if (outslipRef != null && outslipRef.toString().isNotEmpty) {
    try {
      final os = await api.getData(
        '/outslips/${Uri.encodeComponent(outslipRef.toString())}',
      );
      final fromOs = _deliveryFromOutslipRow(delivery, os);
      if (fromOs != null) return fromOs;
    } catch (_) {}
  }

  final cached = await _deliveryFromOfflineCache(delivery, refs);
  if (cached != null) return cached;

  throw ApiException(
    'Could not load delivery line items. Start the API (erp-server: npm start), then tap reload.',
  );
}

bool canMarkDeliveryOut(Map<String, dynamic> row) => row['status']?.toString() == 'active';

/// Warehouse may mark out for delivery; serials are captured while status is active.
bool canMarkDeliveryOutWithSerials(Map<String, dynamic> row) => canMarkDeliveryOut(row);

bool canMarkDeliveryDelivered(Map<String, dynamic> row) {
  final status = row['status']?.toString() ?? '';
  return status == 'active' || status == 'out_for_delivery';
}

int deliveryLineSerialCount(Map<String, dynamic> item) {
  final serials = item['serialNumbers'];
  if (serials is List) {
    return serials
        .where((value) => value?.toString().trim().isNotEmpty == true)
        .length;
  }
  final brandSerial = item['brandSerial']?.toString();
  if (brandSerial != null && brandSerial.trim().isNotEmpty) {
    return brandSerial
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .length;
  }
  return 0;
}

int _deliveryLineQuantityNeeded(Map<String, dynamic> item) {
  final qty = item['quantity'] ?? item['qty'];
  if (qty is num) return qty.round().clamp(0, 999999);
  final parsed = double.tryParse(qty?.toString() ?? '');
  if (parsed == null) return 0;
  return parsed.round().clamp(0, 999999);
}

({int needed, int captured, bool complete}) deliveryLineSerialProgress(
  Map<String, dynamic> item,
) {
  final needed = _deliveryLineQuantityNeeded(item);
  final captured = deliveryLineSerialCount(item);
  return (
    needed: needed,
    captured: captured,
    complete: needed > 0 && captured >= needed,
  );
}

bool deliverySerialsComplete(Map<String, dynamic> delivery) {
  return deliveryOverallSerialProgress(delivery).complete;
}

({int needed, int captured, bool complete}) deliveryOverallSerialProgress(
  Map<String, dynamic> delivery,
) {
  final items = delivery['items'];
  if (items is! List || items.isEmpty) {
    return (needed: 0, captured: 0, complete: false);
  }

  var needed = 0;
  var captured = 0;
  for (final entry in items) {
    if (entry is! Map) continue;
    final progress = deliveryLineSerialProgress(Map<String, dynamic>.from(entry));
    needed += progress.needed;
    captured += progress.captured.clamp(0, progress.needed);
  }

  return (
    needed: needed,
    captured: captured,
    complete: needed > 0 && captured >= needed,
  );
}

bool canMarkDeliveryDeliveredWithSerials(Map<String, dynamic> row) =>
    canMarkDeliveryDelivered(row) && deliverySerialsComplete(row);

bool deliverySerialsPending(Map<String, dynamic> row) =>
    canMarkDeliveryDelivered(row) && !deliverySerialsComplete(row);

bool canScanDeliverySerials(Map<String, dynamic> row, {bool offline = false}) {
  if (offline) return false;
  return row['status']?.toString() == 'active';
}

bool canUpdateDeliveryStatus(Map<String, dynamic> delivery, String nextStatus) {
  switch (nextStatus) {
    case 'out_for_delivery':
      return canMarkDeliveryOutWithSerials(delivery);
    case 'delivered':
      return canMarkDeliveryDeliveredWithSerials(delivery);
    default:
      return false;
  }
}

String deliverySerialsBlockedMessage() =>
    'Capture serial numbers for every line item before marking delivered.';

String? validateDeliveryProductBarcode(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return 'Barcode is empty.';
  if (trimmed.length < 3) return 'Barcode looks too short.';
  if (trimmed.length > 64) return 'Barcode is too long.';
  if (!RegExp(r'^[\w\-\.\/\+\s]+$').hasMatch(trimmed)) {
    return 'Barcode contains invalid characters.';
  }
  return null;
}

String? validateDeliverySerialNumber(String serial) {
  final trimmed = serial.trim();
  if (trimmed.isEmpty) return 'Serial is empty.';
  if (trimmed.length < 3) return 'Serial looks too short.';
  if (trimmed.length > 128) return 'Serial is too long.';
  return null;
}

bool deliverySerialAlreadyUsed(
  List<Map<String, dynamic>> items,
  String serial, {
  int? ignoreLineIndex,
  int? ignoreSerialIndex,
}) {
  final key = serial.trim().toLowerCase();
  if (key.isEmpty) return false;
  for (var lineIndex = 0; lineIndex < items.length; lineIndex++) {
    final raw = items[lineIndex]['serialNumbers'];
    if (raw is! List) continue;
    for (var serialIndex = 0; serialIndex < raw.length; serialIndex++) {
      if (ignoreLineIndex == lineIndex && ignoreSerialIndex == serialIndex) {
        continue;
      }
      if (raw[serialIndex].toString().trim().toLowerCase() == key) {
        return true;
      }
    }
  }
  return false;
}

bool hasBillingForDelivery(Map<String, dynamic> delivery, TransactionLists lists) {
  final drDb = fieldDbId(delivery);
  final drNo = delivery['id']?.toString();
  return lists.billings.any(
    (row) => _idsMatch(row['referenceDrDbId'], drDb) || _idsMatch(row['referenceDrId'], drNo),
  );
}

bool canCreateBillingFromDelivery(Map<String, dynamic> delivery, TransactionLists lists) =>
    delivery['status']?.toString() == 'delivered' && !hasBillingForDelivery(delivery, lists);

bool canRecordBillingPayment(Map<String, dynamic> row) =>
    row['paymentStatus']?.toString() != 'paid';

bool canApproveAccomplishment(Map<String, dynamic> row) {
  final status = row['status']?.toString() ?? '';
  return status != 'approved' && status != 'inactive';
}

bool canEditAccomplishment(Map<String, dynamic> row) {
  final status = row['status']?.toString() ?? '';
  return status != 'approved' && status != 'inactive';
}
