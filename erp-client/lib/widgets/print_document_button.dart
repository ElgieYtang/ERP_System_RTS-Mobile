import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/document_print.dart';
import '../theme/app_theme.dart';

/// Shown when print needs a live API (quotation, PO, DR) or gate pass is not loaded.
const printRequiresConnectionMessage = 'Connect to the internet to print this document.';

class PrintDocumentButton extends StatelessWidget {
  const PrintDocumentButton({
    super.key,
    required this.onPrint,
    this.label = 'Print / PDF',
    this.enabled = true,
    this.disabledTooltip = printRequiresConnectionMessage,
  });

  final Future<void> Function() onPrint;
  final String label;
  final bool enabled;
  final String? disabledTooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: enabled
          ? () async {
              try {
                await onPrint();
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyApiError(error))),
                );
              }
            }
          : null,
      icon: Icon(Icons.print_outlined, color: enabled ? AppTheme.maroon : AppTheme.textSecondary),
      label: Text(label),
    );

    if (!enabled && disabledTooltip != null) {
      return Tooltip(message: disabledTooltip!, child: button);
    }
    return button;
  }
}

Future<void> printQuotation(BuildContext context, dynamic api, Map<String, dynamic> row) =>
    DocumentPrint.shareQuotation(api, row);

Future<void> printPurchaseOrder(BuildContext context, dynamic api, Map<String, dynamic> row) =>
    DocumentPrint.sharePurchaseOrder(api, row);

Future<void> printDeliveryReceipt(BuildContext context, dynamic api, Map<String, dynamic> row) =>
    DocumentPrint.shareDeliveryReceipt(api, row);

Future<void> printSoa({
  required Map<String, dynamic> customer,
  required Map<String, dynamic> account,
}) =>
    DocumentPrint.shareSoa(customer: customer, account: account);

Future<void> printReceiving(Map<String, dynamic> row) => DocumentPrint.shareReceiving(row);

Future<void> printOutslip(ApiClient api, Map<String, dynamic> row) =>
    DocumentPrint.shareOutslip(api, row);

Future<void> printGatePass(
  BuildContext context,
  ApiClient api,
  Map<String, dynamic> row, {
  Map<String, dynamic>? documentOverride,
}) =>
    DocumentPrint.shareGatePass(api, row, documentOverride: documentOverride);

Future<void> printBilling(Map<String, dynamic> row) => DocumentPrint.shareBilling(row);
