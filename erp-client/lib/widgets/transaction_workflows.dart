import 'package:flutter/material.dart';

import '../navigation/mobile_modules.dart';
import '../navigation/module_navigation_scope.dart';
import '../navigation/transaction_navigation.dart';
import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/transaction_actions.dart';
import '../services/transaction_lists.dart';
import 'field_ui.dart';
import 'print_document_button.dart';

void showTransactionActionBlocked(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Map<String, dynamic>? _findReceiving(List<Map<String, dynamic>> receivings, String id) {
  for (final row in receivings) {
    if (row['dbId']?.toString() == id || row['id']?.toString() == id) {
      return row;
    }
  }
  return null;
}

String? _customerIdFromReceiving(Map<String, dynamic>? receiving) {
  final id = receiving?['customerId']?.toString();
  if (id == null || id.isEmpty) return null;
  return id;
}

Future<Map<String, dynamic>?> showCreateOutslipDialog(
  BuildContext context,
  ApiClient api, {
  String? initialReceivingDbId,
  List<Map<String, dynamic>>? completedReceivings,
  TransactionLists? lists,
}) async {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> receivings = completedReceivings ?? [];

  try {
    customers = (await api.getList('/setup/customers'))
        .cast<Map<String, dynamic>>()
        .where((row) => row['status'] != 'Inactive')
        .toList();
    if (receivings.isEmpty) {
      receivings = (await api.getList('/receivings'))
          .cast<Map<String, dynamic>>()
          .where((row) => row['status'] == 'completed')
          .toList();
    }
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }

  if (!context.mounted) return null;
  if (customers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active customers found in setup.')),
    );
    return null;
  }
  if (receivings.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No completed receivings available.')),
    );
    return null;
  }

  if (lists != null) {
    receivings = receivings
        .where((row) => canCreateOutslipFromReceiving(row, lists))
        .toList();
    if (receivings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No receivings with a linked quotation customer are ready for a new outslip.',
          ),
        ),
      );
      return null;
    }
  } else {
    receivings = receivings
        .where((row) => _customerIdFromReceiving(row) != null)
        .toList();
    if (receivings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No completed receivings with a linked quotation customer are available.',
          ),
        ),
      );
      return null;
    }
  }

  var receivingDbId = initialReceivingDbId ??
      receivings.first['dbId']?.toString() ??
      receivings.first['id']?.toString() ??
      '';
  final initialReceiving = _findReceiving(receivings, receivingDbId);
  var customerId = _customerIdFromReceiving(initialReceiving) ?? '';
  if (customerId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This receiving has no quotation customer. Outslip cannot be created.'),
      ),
    );
    return null;
  }

  final created = await showDialog<Object?>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final selectedReceiving = _findReceiving(receivings, receivingDbId);
        final lockedCustomerId = _customerIdFromReceiving(selectedReceiving);
        var customerLabel = selectedReceiving?['customerName']?.toString() ?? '';
        if (customerLabel.isEmpty && lockedCustomerId != null) {
          for (final row in customers) {
            if (row['id']?.toString() == lockedCustomerId) {
              customerLabel = row['name']?.toString() ?? 'Customer';
              break;
            }
          }
        }
        if (customerLabel.isEmpty) {
          customerLabel = 'Customer';
        }

        return AlertDialog(
        title: const Text('New outslip'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        content: FieldDialogForm(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('outslip-receiving-$receivingDbId'),
              isExpanded: true,
              initialValue: receivingDbId.isEmpty ? null : receivingDbId,
              decoration: const InputDecoration(
                labelText: 'From receiving (completed)',
                border: OutlineInputBorder(),
              ),
              items: receivings
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['dbId']?.toString() ?? row['id']?.toString() ?? '',
                      child: Text(
                        '${row['id'] ?? 'RCV'} — ${row['supplierName'] ?? 'Receiving'}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setDialogState(() {
                receivingDbId = value ?? receivingDbId;
                final linked = _customerIdFromReceiving(_findReceiving(receivings, receivingDbId));
                customerId = linked ?? '';
              }),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
                helperText: 'Set from the quotation linked to this receiving.',
              ),
              child: Text(
                customerLabel,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (lockedCustomerId == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This receiving has no quotation customer. Outslip cannot be created.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: lockedCustomerId == null
                ? null
                : () async {
              final customer = int.tryParse(customerId);
              final receiving = int.tryParse(receivingDbId);
              if (customer == null || receiving == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Select a customer and receiving.')),
                );
                return;
              }
              final linkedCustomerId = _customerIdFromReceiving(
                _findReceiving(receivings, receivingDbId),
              );
              if (linkedCustomerId == null || customer.toString() != linkedCustomerId) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This receiving has no quotation customer. Outslip cannot be created.',
                    ),
                  ),
                );
                return;
              }
              try {
                final response = await api.post('/outslips', {
                  'customerId': customer,
                  'receivingId': receiving,
                });
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext, rootNavigator: true).pop(recordFromPayload(response));
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(friendlyApiError(error))),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
      },
    ),
  );

  if (created is Map<String, dynamic>) {
    return Map<String, dynamic>.from(created);
  }
  if (created is Map) {
    return Map<String, dynamic>.from(created);
  }
  return null;
}

Future<Map<String, dynamic>?> confirmCreateDeliveryReceipt(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canCreateDrFromOutslip(outslip, lists)) {
    showTransactionActionBlocked(
      context,
      'This outslip is not ready for a delivery receipt.',
    );
    return null;
  }

  final outslipId = int.tryParse(fieldDbId(outslip));
  if (outslipId == null) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create delivery receipt?'),
      content: Text('Create DR from ${outslip['id'] ?? 'outslip'}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/delivery-receipts', {'outslipId': outslipId});
    if (context.mounted) {
      final drId = recordFromPayload(response)?['id']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            drId != null && drId.isNotEmpty
                ? 'Delivery receipt $drId created.'
                : 'Delivery receipt created.',
          ),
          action: SnackBarAction(
            label: 'Deliveries',
            onPressed: () {
              final scope = ModuleNavigationScope.maybeOf(context);
              if (scope != null) {
                scope.onOpenModule(context, MobileModule.deliveries);
              }
            },
          ),
        ),
      );
    }
    return mergeRecordFromMutation(
      const {},
      response,
      fallbackPatch: const {'status': 'active'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> receivePurchaseOrder(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> po,
  TransactionLists lists,
) async {
  final id = fieldDbId(po);
  if (id.isEmpty) return null;

  final existing = findReceivingForPo(po, lists);
  if (existing != null) {
    return existing;
  }

  if (!canReceivePurchaseOrder(po, lists)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This purchase order cannot receive items.')),
      );
    }
    return null;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create receiving?'),
      content: Text('Start receiving for ${po['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/purchase-orders/$id/receivings');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiving created.')),
      );
    }
    return recordFromPayload(response);
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> confirmReceiving(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> receiving,
) async {
  if (!canConfirmReceiving(receiving)) {
    showTransactionActionBlocked(context, 'This receiving is already completed.');
    return null;
  }

  final id = fieldDbId(receiving);
  if (id.isEmpty) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm receiving'),
      content: Text('Confirm ${receiving['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/receivings/$id/confirm');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receiving confirmed')),
      );
    }
    return mergeRecordFromMutation(
      receiving,
      response,
      fallbackPatch: const {'status': 'completed'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> createOutslipFromReceiving(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> receiving,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canCreateOutslipFromReceiving(receiving, lists)) {
    showTransactionActionBlocked(
      context,
      'This receiving is not completed, has no quotation customer, or already has an outslip.',
    );
    return null;
  }

  return showCreateOutslipDialog(
    context,
    api,
    initialReceivingDbId: fieldDbId(receiving),
    lists: lists,
    completedReceivings: [receiving],
  );
}

Future<Map<String, dynamic>?> approveOutslip(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip,
) async {
  if (!canApproveOutslip(outslip)) {
    showTransactionActionBlocked(context, 'Only pending outslips can be approved.');
    return null;
  }

  final id = fieldDbId(outslip);
  if (id.isEmpty) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Approve outslip?'),
      content: Text('Approve ${outslip['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/outslips/$id/approve');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outslip approved.')),
      );
    }
    return mergeRecordFromMutation(
      outslip,
      response,
      fallbackPatch: const {'status': 'approved'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> dispatchOutslip(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip,
) async {
  if (!canDispatchOutslip(outslip)) {
    showTransactionActionBlocked(context, 'Only approved outslips can be dispatched.');
    return null;
  }

  final id = fieldDbId(outslip);
  if (id.isEmpty) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Dispatch outslip?'),
      content: Text('Dispatch ${outslip['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Dispatch')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/outslips/$id/dispatch');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outslip dispatched')),
      );
    }
    return mergeRecordFromMutation(
      outslip,
      response,
      fallbackPatch: const {'status': 'for_dispatch'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> fetchSetupItemByBarcode(
  ApiClient api,
  String barcode,
) async {
  final code = barcode.trim();
  if (code.isEmpty) return null;
  try {
    return await api.getData('/setup/items/by-barcode/${Uri.encodeComponent(code)}');
  } on ApiException catch (error) {
    if (error.statusCode == 404) return null;
    rethrow;
  }
}

List<Map<String, dynamic>> buildDeliverySerialLines(
  List<Map<String, dynamic>> items,
) {
  return items.map((item) {
    final productId = int.tryParse(item['productId']?.toString() ?? '');
    if (productId == null) {
      throw FormatException('Missing product id on a delivery line.');
    }
    final serialNumbers = <String>[];
    final raw = item['serialNumbers'];
    if (raw is List) {
      for (final value in raw) {
        final text = value.toString().trim();
        if (text.isNotEmpty) {
          serialNumbers.add(text);
        }
      }
    }
    return {
      'productId': productId,
      'serialNumbers': serialNumbers,
    };
  }).toList();
}

Future<Map<String, dynamic>?> updateDeliverySerials(
  ApiClient api,
  Map<String, dynamic> delivery,
  List<Map<String, dynamic>> items,
) async {
  final id = fieldDbId(delivery);
  if (id.isEmpty) return null;

  final response = await api.put('/delivery-receipts/$id/serials', {
    'lines': buildDeliverySerialLines(items),
  });
  return mergeRecordFromMutation(delivery, response);
}

Future<Map<String, dynamic>?> updateDeliveryStatus(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> delivery,
  String status,
) async {
  if (!canUpdateDeliveryStatus(delivery, status)) {
    final message = status == 'delivered' && deliverySerialsPending(delivery)
        ? deliverySerialsBlockedMessage()
        : 'This delivery cannot move to that status.';
    showTransactionActionBlocked(context, message);
    return null;
  }

  final id = fieldDbId(delivery);
  if (id.isEmpty) return null;

  final label = fieldStatusLabel(status);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Mark as $label?'),
      content: Text('Update ${delivery['id'] ?? id} to "$label".'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/delivery-receipts/$id/status', {'status': status});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated to $label')),
      );
    }
    return mergeRecordFromMutation(
      delivery,
      response,
      fallbackPatch: {'status': status},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> recordBillingPayment(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> billing,
) async {
  if (!canRecordBillingPayment(billing)) {
    showTransactionActionBlocked(context, 'This billing is already paid.');
    return null;
  }

  final id = fieldRowId(billing);
  if (id.isEmpty) return null;

  Map<String, dynamic> snapshot = billing;
  try {
    snapshot = await api.getOne('/billings/${Uri.encodeComponent(id)}');
  } catch (_) {
    // Use list row if refresh fails (offline).
  }

  final remaining = fieldBillingBalanceDue(snapshot).toDouble().clamp(0, double.infinity);
  final amountController = TextEditingController(text: fieldRoundMoney(remaining).toStringAsFixed(2));
  final referenceController = TextEditingController();
  final remarksController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Balance: ${fieldFormatMoney(remaining)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            TextField(
              controller: referenceController,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
            ),
            TextField(
              controller: remarksController,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    ),
  );
  if (confirmed != true) return null;

  final parsed = double.tryParse(amountController.text.trim());
  if (parsed == null || parsed <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid payment amount.')),
      );
    }
    return null;
  }

  var amount = fieldRoundMoney(parsed);
  if (amount > remaining) {
    if (amount - remaining <= 0.05) {
      amount = fieldRoundMoney(remaining);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Amount cannot exceed ${fieldFormatMoney(remaining)}.')),
      );
      return null;
    } else {
      return null;
    }
  }

  try {
    final response = await api.post('/billings/${Uri.encodeComponent(id)}/payments', {
      'amount': amount,
      'date': DateTime.now().toIso8601String().split('T').first,
      if (referenceController.text.trim().isNotEmpty) 'reference': referenceController.text.trim(),
      if (remarksController.text.trim().isNotEmpty) 'remarks': remarksController.text.trim(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded.')),
      );
    }
    return mergeRecordFromMutation(billing, response);
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> editQuotation(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> quotation,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canEditQuotation(quotation, lists)) {
    showTransactionActionBlocked(
      context,
      'This quotation cannot be edited after a purchase order exists.',
    );
    return null;
  }

  final id = fieldRowId(quotation);
  if (id.isEmpty) return null;

  final rawDate = quotation['date']?.toString() ?? '';
  var selectedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
  var status = quotation['status']?.toString() ?? 'pending';

  if (!context.mounted) return null;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Edit quotation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => status = value);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (saved != true) return null;

  final dateStr =
      '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

  try {
    final response = await api.put('/quotations/$id', {
      'date': dateStr,
      'status': status,
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation updated.')),
      );
    }
    return mergeRecordFromMutation(quotation, response, fallbackPatch: {'status': status});
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> approveQuotation(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> quotation,
) async {
  if (!canApproveQuotation(quotation)) {
    showTransactionActionBlocked(context, 'Only pending quotations can be approved.');
    return null;
  }

  final id = fieldRowId(quotation);
  if (id.isEmpty) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Approve quotation?'),
      content: Text('Approve ${quotation['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.put('/quotations/$id', {'status': 'approved'});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation approved.')),
      );
    }
    return mergeRecordFromMutation(
      quotation,
      response,
      fallbackPatch: const {'status': 'approved'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> cancelQuotation(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> quotation,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canCancelQuotation(quotation, lists)) {
    showTransactionActionBlocked(
      context,
      'This quotation cannot be cancelled after a purchase order exists.',
    );
    return null;
  }

  final id = fieldRowId(quotation);
  if (id.isEmpty) return null;

  if (!context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel quotation?'),
      content: Text('Cancel ${quotation['id'] ?? id}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/quotations/$id/cancel');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation cancelled.')),
      );
    }
    return mergeRecordFromMutation(
      quotation,
      response,
      fallbackPatch: const {'status': 'cancelled'},
    );
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> convertQuotationToPo(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> quotation,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canConvertQuotation(quotation, lists)) {
    showTransactionActionBlocked(
      context,
      'Only approved quotations without a PO can be converted.',
    );
    return null;
  }

  final id = fieldRowId(quotation);
  if (id.isEmpty) return null;

  List<Map<String, dynamic>> suppliers = [];
  try {
    suppliers = (await api.getList('/setup/suppliers')).cast<Map<String, dynamic>>();
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }

  final active = suppliers.where((s) => s['status'] != 'Inactive').toList();
  if (active.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active suppliers found in setup.')),
      );
    }
    return null;
  }

  var supplierId = active.first['id']?.toString() ?? '';
  if (!context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Convert to purchase order'),
        content: DropdownButtonFormField<String>(
          key: ValueKey('convert-supplier-$supplierId'),
          initialValue: supplierId,
          decoration: const InputDecoration(labelText: 'Supplier'),
          items: active
              .map(
                (s) => DropdownMenuItem(
                  value: s['id']?.toString() ?? '',
                  child: Text(s['name']?.toString() ?? 'Supplier'),
                ),
              )
              .toList(),
          onChanged: (value) => setDialogState(() => supplierId = value ?? supplierId),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Convert')),
        ],
      ),
    ),
  );
  if (confirmed != true || supplierId.isEmpty) return null;

  try {
    final response = await api.post('/quotations/$id/convert-to-po', {
      'supplierId': int.parse(supplierId),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase order created from quotation.')),
      );
    }
    return mergeRecordFromMutation(const {}, response);
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> confirmCreateBilling(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> delivery,
) async {
  final lists = await TransactionLists.load(api);
  if (!context.mounted) return null;
  if (!canCreateBillingFromDelivery(delivery, lists)) {
    showTransactionActionBlocked(
      context,
      'Billing already exists or delivery is not marked delivered.',
    );
    return null;
  }

  final deliveryId = int.tryParse(fieldDbId(delivery));
  if (deliveryId == null) return null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create billing?'),
      content: Text('Create billing for ${delivery['id'] ?? 'delivery'}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
      ],
    ),
  );
  if (ok != true) return null;

  try {
    final response = await api.post('/billings', {'deliveryId': deliveryId});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing statement created.')),
      );
    }
    return recordFromPayload(response);
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>> fetchGatePassDocument(
  ApiClient api,
  Map<String, dynamic> outslip,
) async {
  final ref = fieldDbId(outslip);
  if (ref.isEmpty) throw ApiException('Outslip reference missing.');

  final response = await api.request('GET', '/outslips/$ref/gate-pass');
  final data = (response as Map)['data'];
  if (data is! Map) throw ApiException('Gate pass not found.');
  return Map<String, dynamic>.from(data);
}

Future<Map<String, dynamic>?> saveGatePassDetails(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip, {
  required Map<String, dynamic> payload,
  required Map<String, dynamic> currentDocument,
  bool offline = false,
}) async {
  if (!canEditGatePass(currentDocument, offline: offline)) {
    showTransactionActionBlocked(
      context,
      gatePassEditBlockedMessage(offline: offline),
    );
    return null;
  }

  final ref = fieldDbId(outslip);
  if (ref.isEmpty) return null;

  try {
    final response = await api.put('/outslips/$ref/gate-pass', payload);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gate pass saved.')),
      );
    }
    final updated = recordFromPayload(response);
    if (updated != null) return updated;
    final data = (response as Map)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<Map<String, dynamic>?> markGatePassAsExited(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip, {
  required Map<String, dynamic> payload,
  required Map<String, dynamic> currentDocument,
  bool offline = false,
}) async {
  if (!canMarkGatePassExited(currentDocument, offline: offline)) {
    showTransactionActionBlocked(
      context,
      gatePassExitBlockedMessage(offline: offline),
    );
    return null;
  }

  final ref = fieldDbId(outslip);
  if (ref.isEmpty) return null;

  try {
    await api.put('/outslips/$ref/gate-pass', payload);
    final response = await api.post('/outslips/$ref/gate-pass/exit');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gate pass marked as exited.')),
      );
    }
    final updated = recordFromPayload(response);
    if (updated != null) return updated;
    final data = (response as Map)['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    return null;
  }
}

Future<void> printGatePassDocument(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> outslip, {
  required Map<String, dynamic> document,
}) async {
  if (!canPrintGatePass(outslip)) {
    showTransactionActionBlocked(
      context,
      'Gate pass is available after outslip approval.',
    );
    return;
  }

  await printGatePass(context, api, outslip, documentOverride: document);
}
