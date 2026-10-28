import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'amount_to_words.dart';
import 'api_client.dart';
import 'document_pdf_layout.dart';
import '../widgets/field_ui.dart';

class DocumentPrint {
  DocumentPrint._();

  static final _statementDate = DateFormat('MMM d, yyyy', 'en_US');

  static Future<void> shareQuotation(
    ApiClient api,
    Map<String, dynamic> quotation,
  ) async {
    final customer = await _loadCustomer(api, quotation['customerId']);
    final items = _itemsFromRow(quotation);
    final total = _grandTotal(quotation, items);
    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('QUOTATION'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('To:', customer?['name']?.toString() ?? quotation['customerName']?.toString()),
                    DocumentPdfLayout.fieldLine('Address:', customer?['address']?.toString()),
                    DocumentPdfLayout.fieldLine('Telephone No.:', customer?['phone']?.toString() ?? customer?['contactNo']?.toString()),
                    DocumentPdfLayout.fieldLine('TIN No.:', (customer?['tinNo'] ?? customer?['tin'])?.toString()),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.SizedBox(
                width: 180,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('No.:', quotation['id']?.toString(), labelWidth: 48),
                    DocumentPdfLayout.fieldLine(
                      'Date:',
                      quotation['displayDate']?.toString() ?? quotation['date']?.toString(),
                      labelWidth: 48,
                    ),
                  ],
                ),
              ),
            ],
          ),
          DocumentPdfLayout.subjectLine(quotation['subject']?.toString()),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.singleRule(),
          DocumentPdfLayout.buildQuotationTable(items: items, headerColor: DocumentPdfLayout.greenHeader),
          DocumentPdfLayout.grandTotal(total),
          DocumentPdfLayout.quotationFooter(
            conformeName: customer?['name']?.toString() ?? quotation['customerName']?.toString() ?? '',
            conformeHint: 'Signature Over Printed Name of Customer',
          ),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${quotation['id'] ?? 'quotation'}.pdf');
  }

  static Future<void> sharePurchaseOrder(
    ApiClient api,
    Map<String, dynamic> order,
  ) async {
    final supplier = await _loadSupplier(api, order['supplierId']);
    final items = _itemsFromRow(order);
    final total = _grandTotal(order, items);
    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('PURCHASE ORDER'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('Supplier:', supplier?['name']?.toString() ?? order['supplierName']?.toString()),
                    DocumentPdfLayout.fieldLine('Address:', supplier?['address']?.toString()),
                    DocumentPdfLayout.fieldLine(
                      'Telephone No.:',
                      supplier?['phone']?.toString() ??
                          supplier?['contactPersonNo']?.toString() ??
                          supplier?['contactPerson']?.toString(),
                    ),
                    DocumentPdfLayout.fieldLine('TIN No.:', (supplier?['tinNo'] ?? supplier?['tin'])?.toString()),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.SizedBox(
                width: 180,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('P.O. No.:', order['id']?.toString(), labelWidth: 58),
                    DocumentPdfLayout.fieldLine(
                      'Date:',
                      order['displayDate']?.toString() ?? order['date']?.toString(),
                      labelWidth: 58,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Gentlemen/Mesdames: Please deliver to this Office the following articles subject to the terms and conditions contained herein:',
            style: DocumentPdfLayout.body,
          ),
          pw.SizedBox(height: 8),
          _poDeliveryGrid(order),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.singleRule(),
          DocumentPdfLayout.buildQuotationTable(items: _poItems(items), headerColor: DocumentPdfLayout.grayHeader),
          DocumentPdfLayout.grandTotal(total),
          _amountInWords(total),
          pw.SizedBox(height: 10),
          pw.Text(
            'In case of failure to make full delivery within the time specified above, a penalty of one-tenth (1/10) of one percent for everyday of delay shall be imposed.',
            style: DocumentPdfLayout.small.copyWith(fontStyle: pw.FontStyle.italic),
          ),
          DocumentPdfLayout.quotationFooter(
            conformeName: supplier?['name']?.toString() ?? order['supplierName']?.toString() ?? '',
            conformeHint: 'Signature Over Printed Name of Supplier',
          ),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${order['id'] ?? 'purchase-order'}.pdf');
  }

  static Future<void> shareDeliveryReceipt(
    ApiClient api,
    Map<String, dynamic> delivery,
  ) async {
    final detail = await _ensureDeliveryDetail(api, delivery);
    final customer = await _loadCustomer(api, detail['customerId']);
    final outslip = await _loadOutslip(api, detail);
    var items = _itemsFromRow(detail);
    if (items.isEmpty && outslip != null) {
      items = _itemsFromRow(outslip);
    }
    final total = _grandTotal(detail, items);
    final reference = detail['reference']?.toString() ??
        [
          detail['referenceOutslipId'],
          outslip?['referencePoId'],
        ].where((v) => v != null && v.toString().isNotEmpty).join(' / ');

    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('DELIVERY RECEIPT'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Delivered to:', style: DocumentPdfLayout.bodyBold),
                    pw.SizedBox(height: 4),
                    pw.Text(customer?['name']?.toString() ?? detail['customerName']?.toString() ?? ' ', style: DocumentPdfLayout.body),
                    if ((customer?['address']?.toString() ?? '').isNotEmpty)
                      pw.Text(customer!['address'].toString(), style: DocumentPdfLayout.body),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.SizedBox(
                width: 180,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine(
                      'Date:',
                      detail['displayDate']?.toString() ?? detail['date']?.toString(),
                      labelWidth: 72,
                    ),
                    DocumentPdfLayout.fieldLine('Delivery No.:', detail['id']?.toString(), labelWidth: 72),
                  ],
                ),
              ),
            ],
          ),
          DocumentPdfLayout.referenceBar('Reference:', reference),
          DocumentPdfLayout.buildDeliveryTable(items: items, total: total),
          pw.SizedBox(height: 10),
          pw.Text(
            'I/We acknowledged to have received in good order and condition the above merchandise(s) in accordance to the specifications stated subject to the terms and conditions.',
            style: DocumentPdfLayout.small.copyWith(fontStyle: pw.FontStyle.italic),
          ),
          DocumentPdfLayout.deliveredFooter(),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${detail['id'] ?? 'delivery'}.pdf');
  }

  static Future<void> shareSoa({
    required Map<String, dynamic> customer,
    required Map<String, dynamic> account,
  }) async {
    final rows = (account['rows'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final debitRows = rows.where((row) => ((row['debit'] as num?)?.toDouble() ?? 0) > 0).toList();
    final totals = (account['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final totalAmount = (totals['totalDebit'] as num?)?.toDouble() ??
        debitRows.fold<double>(0, (sum, row) => sum + ((row['debit'] as num?)?.toDouble() ?? 0));
    final paymentsApplied = (totals['totalCredit'] as num?)?.toDouble() ?? 0;
    final balanceDue = (totals['outstanding'] as num?)?.toDouble() ?? (totalAmount - paymentsApplied);

    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('STATEMENT OF ACCOUNT'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      (account['customerName'] ?? customer['name'] ?? '').toString().toUpperCase(),
                      style: DocumentPdfLayout.bodyBold.copyWith(fontSize: 12),
                    ),
                    if ((account['customerAddress'] ?? customer['address'] ?? '').toString().isNotEmpty)
                      pw.Text(
                        (account['customerAddress'] ?? customer['address']).toString(),
                        style: DocumentPdfLayout.body.copyWith(fontStyle: pw.FontStyle.italic),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.SizedBox(
                width: 200,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('Statement date:', _formatStatementDate(account), labelWidth: 88),
                    DocumentPdfLayout.fieldLine('Statement No.:', _buildStatementNo(account, customer), labelWidth: 88),
                  ],
                ),
              ),
            ],
          ),
          DocumentPdfLayout.referenceBar('Reference', _buildReference(account)),
          DocumentPdfLayout.sectionLabel('Account Activity'),
          DocumentPdfLayout.buildSoaTable(
            debitRows: debitRows,
            totalAmount: totalAmount,
            paymentsApplied: paymentsApplied,
            balanceDue: balanceDue,
          ),
          DocumentPdfLayout.soaFooter(),
        ]);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'SOA-${customer['id'] ?? 'customer'}.pdf',
    );
  }

  static Future<void> shareReceiving(Map<String, dynamic> receiving) async {
    final items = _itemsFromRow(receiving);
    final total = _grandTotal(receiving, items);
    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('RECEIVING REPORT'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          DocumentPdfLayout.fieldLine('Receiving No.:', receiving['id']?.toString()),
          DocumentPdfLayout.fieldLine(
            'Date:',
            receiving['displayDate']?.toString() ?? receiving['date']?.toString(),
          ),
          DocumentPdfLayout.fieldLine('Supplier:', receiving['supplierName']?.toString()),
          DocumentPdfLayout.fieldLine('Purchase Order:', receiving['purchaseOrderId']?.toString()),
          DocumentPdfLayout.fieldLine('Status:', receiving['status']?.toString()),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.singleRule(),
          DocumentPdfLayout.buildQuotationTable(items: items, headerColor: DocumentPdfLayout.grayHeader),
          DocumentPdfLayout.grandTotal(total),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${receiving['id'] ?? 'receiving'}.pdf');
  }

  static Future<void> shareGatePass(
    ApiClient api,
    Map<String, dynamic> outslip, {
    Map<String, dynamic>? documentOverride,
  }) async {
    Map<String, dynamic>? document = documentOverride;

    if (document == null) {
      final detail = await _ensureOutslipDetail(api, outslip);
      final outslipRef = _documentRef(detail);

      if (outslipRef.isNotEmpty) {
        final response = await api.request('GET', '/outslips/$outslipRef/gate-pass');
        if (response is Map && response['data'] is Map) {
          document = Map<String, dynamic>.from(response['data'] as Map);
        }
      }
    }

    if (document == null) {
      throw ApiException('Could not load gate pass data. Check your connection and try again.');
    }

    final Map<String, dynamic> doc = document;

    String dash(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? '—' : text;
    }

    final items = (doc['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final gatePassNo = doc['gatePassNo']?.toString() ?? 'gate-pass';

    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('GATE PASS'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine('Released to:', doc['customerName']?.toString(), labelWidth: 88),
                    DocumentPdfLayout.fieldLine('Destination:', doc['destination']?.toString(), labelWidth: 88),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.SizedBox(
                width: 180,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    DocumentPdfLayout.fieldLine(
                      'Date:',
                      doc['displayDate']?.toString() ?? doc['date']?.toString(),
                      labelWidth: 88,
                    ),
                    DocumentPdfLayout.fieldLine('Time Out:', doc['displayTimeOut']?.toString(), labelWidth: 88),
                    DocumentPdfLayout.fieldLine('Gate Pass No.:', doc['gatePassNo']?.toString(), labelWidth: 88),
                    DocumentPdfLayout.fieldLine('Outslip No.:', doc['outslipNo']?.toString(), labelWidth: 88),
                    DocumentPdfLayout.fieldLine('PO No.:', doc['purchaseOrderNo']?.toString(), labelWidth: 88),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Purpose: ${doc['purpose']?.toString() ?? 'Delivery of items per Outslip'}',
            style: DocumentPdfLayout.body,
          ),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.fieldLine('Vehicle:', doc['vehicleNo']?.toString()),
          DocumentPdfLayout.fieldLine('Plate No.:', doc['plateNo']?.toString()),
          DocumentPdfLayout.fieldLine('Driver:', doc['driverName']?.toString()),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.singleRule(),
          DocumentPdfLayout.buildGatePassTable(items: items),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Remarks', style: DocumentPdfLayout.bodyBold),
                pw.SizedBox(height: 4),
                pw.Text(dash(doc['remarks']?.toString()), style: DocumentPdfLayout.body),
              ],
            ),
          ),
          DocumentPdfLayout.gatePassFooterQuad(
            preparedBy: doc['preparedByName']?.toString() ?? 'WEB ADMINISTRATOR',
            authorizedBy: doc['authorizedByName']?.toString() ?? 'Admin',
          ),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '$gatePassNo.pdf');
  }

  static Future<void> shareOutslip(
    ApiClient api,
    Map<String, dynamic> outslip,
  ) async {
    final detail = await _ensureOutslipDetail(api, outslip);
    final items = _itemsFromRow(detail);
    final total = _grandTotal(detail, items);
    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('OUTSLIP'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          DocumentPdfLayout.fieldLine('Outslip No.:', detail['id']?.toString()),
          DocumentPdfLayout.fieldLine(
            'Date:',
            detail['displayDate']?.toString() ?? detail['date']?.toString(),
          ),
          DocumentPdfLayout.fieldLine('Customer:', detail['customerName']?.toString()),
          DocumentPdfLayout.fieldLine(
            'Receiving:',
            detail['referenceReceivingNo']?.toString() ??
                detail['receivingId']?.toString(),
          ),
          DocumentPdfLayout.fieldLine('Status:', detail['status']?.toString()),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.singleRule(),
          DocumentPdfLayout.buildQuotationTable(items: items, headerColor: DocumentPdfLayout.grayHeader),
          DocumentPdfLayout.grandTotal(total),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${detail['id'] ?? 'outslip'}.pdf');
  }

  static Future<void> shareBilling(Map<String, dynamic> billing) async {
    final total = fieldBillingTotal(billing).toDouble();
    final paid = fieldBillingPaid(billing).toDouble();
    final balance = (total - paid).clamp(0, double.infinity);
    final bytes = await _buildPdf((logo) => [
          DocumentPdfLayout.letterhead(logo),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.centeredTitle('BILLING STATEMENT'),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.doubleRule(),
          pw.SizedBox(height: 4),
          DocumentPdfLayout.fieldLine('Billing No.:', billing['id']?.toString()),
          DocumentPdfLayout.fieldLine(
            'Date:',
            billing['displayDate']?.toString() ?? billing['billingDate']?.toString(),
          ),
          DocumentPdfLayout.fieldLine('Customer:', billing['customerName']?.toString()),
          DocumentPdfLayout.fieldLine('Delivery receipt:', billing['referenceDrId']?.toString()),
          DocumentPdfLayout.fieldLine('Payment status:', billing['paymentStatus']?.toString()),
          pw.SizedBox(height: 8),
          DocumentPdfLayout.fieldLine('Total amount:', DocumentPdfLayout.formatMoney(total)),
          DocumentPdfLayout.fieldLine('Amount paid:', DocumentPdfLayout.formatMoney(paid)),
          DocumentPdfLayout.fieldLine('Balance due:', DocumentPdfLayout.formatMoney(balance)),
          pw.SizedBox(height: 16),
          DocumentPdfLayout.soaFooter(),
        ]);
    await Printing.sharePdf(bytes: bytes, filename: '${billing['id'] ?? 'billing'}.pdf');
  }

  static List<Map<String, dynamic>> _itemsFromRow(Map<String, dynamic> row) {
    return (row['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static List<Map<String, dynamic>> _poItems(List<Map<String, dynamic>> items) {
    return items
        .map((item) => {
              ...item,
              'unit': item['unit']?.toString() ?? 'UNITS',
            })
        .toList();
  }

  static double _grandTotal(Map<String, dynamic> row, List<Map<String, dynamic>> items) {
    return (row['total'] as num?)?.toDouble() ??
        items.fold<double>(0, (sum, item) {
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final price = (item['unitPrice'] as num?)?.toDouble() ?? 0;
          return sum + qty * price;
        });
  }

  static pw.Widget _poDeliveryGrid(Map<String, dynamic> order) {
    final fields = [
      ('Place of Delivery:', order['placeOfDelivery']?.toString() ?? 'Rm 301-E3 Medalle Building, Fuente Osmena, Cebu City'),
      ('Date of Delivery:', order['dateOfDelivery']?.toString() ?? 'On or before ________, 2026'),
      ('Warranty Period:', order['warrantyPeriod']?.toString() ?? 'One (1) Year Warranty from Date of Delivery'),
      ('Project:', order['project']?.toString()),
      ('Delivery Term:', order['deliveryTerm']?.toString()),
      ('Payment Term:', order['paymentTerm']?.toString()),
    ];
    return pw.Column(
      children: [
        for (var i = 0; i < fields.length; i += 2) ...[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: DocumentPdfLayout.fieldLine(fields[i].$1, fields[i].$2, labelWidth: 118)),
              pw.SizedBox(width: 24),
              if (i + 1 < fields.length)
                pw.Expanded(child: DocumentPdfLayout.fieldLine(fields[i + 1].$1, fields[i + 1].$2, labelWidth: 118)),
            ],
          ),
        ],
      ],
    );
  }

  static pw.Widget _amountInWords(double total) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.black)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 168, child: pw.Text('TOTAL AMOUNT IN WORDS:', style: DocumentPdfLayout.bodyBold)),
          pw.Expanded(child: pw.Text(amountToPesoWords(total), style: DocumentPdfLayout.bodyBold)),
        ],
      ),
    );
  }

  static String _formatStatementDate(Map<String, dynamic> account) {
    final raw = account['to'] ?? account['generatedAt'];
    if (raw == null) return _statementDate.format(DateTime.now());
    final parsed = DateTime.tryParse(raw.toString());
    return parsed != null ? _statementDate.format(parsed) : raw.toString();
  }

  static String _buildStatementNo(Map<String, dynamic> account, Map<String, dynamic> customer) {
    final raw = account['to'];
    final date = raw != null ? DateTime.tryParse(raw.toString()) ?? DateTime.now() : DateTime.now();
    final ymd = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final id = (account['customerId'] ?? customer['id'] ?? '0').toString().replaceAll(RegExp(r'\D'), '');
    final suffix = id.padLeft(3, '0');
    return '$ymd${suffix.length > 3 ? suffix.substring(suffix.length - 3) : suffix}';
  }

  static String _buildReference(Map<String, dynamic> account) {
    if ((account['reference']?.toString() ?? '').isNotEmpty) {
      return account['reference'].toString();
    }
    final refs = (account['rows'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((row) => ((row['debit'] as num?)?.toDouble() ?? 0) > 0)
        .map((row) => row['ref']?.toString())
        .whereType<String>()
        .where((ref) => ref.isNotEmpty)
        .take(3)
        .toList();
    if (refs.isNotEmpty) return refs.join(' / ');
    return account['periodLabel']?.toString() ?? '';
  }

  static Future<Map<String, dynamic>?> _loadCustomer(ApiClient api, dynamic id) async {
    if (id == null) return null;
    try {
      final rows = await api.getList('/setup/customers');
      return rows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == id.toString(),
            orElse: () => null,
          );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _loadSupplier(ApiClient api, dynamic id) async {
    if (id == null) return null;
    try {
      final rows = await api.getList('/setup/suppliers');
      return rows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == id.toString(),
            orElse: () => null,
          );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _loadOutslip(
    ApiClient api,
    Map<String, dynamic> delivery,
  ) async {
    final refId = delivery['referenceOutslipId'] ?? delivery['referenceOutslipDbId'];
    if (refId == null) return null;
    try {
      final response = await api.request('GET', '/outslips/${Uri.encodeComponent(refId.toString())}');
      if (response is Map && response['data'] is Map) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
    } catch (_) {}
    try {
      final rows = await api.getList('/outslips');
      return rows.cast<Map<String, dynamic>?>().firstWhere(
            (row) =>
                row?['id']?.toString() == refId.toString() ||
                row?['dbId']?.toString() == refId.toString(),
            orElse: () => null,
          );
    } catch (_) {
      return null;
    }
  }

  static bool _deliveryDetailNeedsRefresh(Map<String, dynamic> delivery) {
    final total = (delivery['total'] as num?)?.toDouble();
    final items = delivery['items'] as List?;
    if (items == null || items.isEmpty) return true;
    if (total == null || total <= 0) return true;
    for (final entry in items) {
      if (entry is! Map) continue;
      final price = (entry['unitPrice'] as num?)?.toDouble() ?? 0;
      if (price <= 0) return true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> _ensureDeliveryDetail(
    ApiClient api,
    Map<String, dynamic> delivery,
  ) async {
    if (!_deliveryDetailNeedsRefresh(delivery)) return delivery;

    final ref = delivery['id']?.toString() ?? delivery['dbId']?.toString() ?? '';
    if (ref.isEmpty) return delivery;

    try {
      final response = await api.request('GET', '/delivery-receipts/${Uri.encodeComponent(ref)}');
      if (response is Map && response['data'] is Map) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
    } catch (_) {}

    try {
      final rows = (await api.getList('/delivery-receipts')).cast<Map<String, dynamic>>();
      for (final row in rows) {
        if (row['id']?.toString() == ref || row['dbId']?.toString() == delivery['dbId']?.toString()) {
          return Map<String, dynamic>.from(row);
        }
      }
    } catch (_) {}

    return delivery;
  }

  static Future<Uint8List> _buildPdf(List<pw.Widget> Function(pw.MemoryImage logo) build) async {
    final logoData = await rootBundle.load('assets/logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: DocumentPdfLayout.pageFormat,
        margin: DocumentPdfLayout.margin,
        build: (context) => build(logo),
      ),
    );
    return doc.save();
  }

  static String _documentRef(Map<String, dynamic> row) {
    final dbId = row['dbId']?.toString();
    if (dbId != null && dbId.isNotEmpty) return dbId;
    return row['id']?.toString() ?? '';
  }

  static bool _outslipDetailNeedsRefresh(Map<String, dynamic> outslip) {
    final items = outslip['items'] as List?;
    if (items == null || items.isEmpty) return true;
    for (final entry in items) {
      if (entry is! Map) continue;
      final price = (entry['unitPrice'] as num?)?.toDouble() ?? 0;
      final name = entry['productName']?.toString() ?? '';
      if (price <= 0 || name.startsWith('Item #')) return true;
    }
    final total = (outslip['total'] as num?)?.toDouble();
    if (total == null || total <= 0) {
      var sum = 0.0;
      for (final entry in items) {
        if (entry is! Map) continue;
        final qty = (entry['quantity'] as num?)?.toDouble() ?? 0;
        final price = (entry['unitPrice'] as num?)?.toDouble() ?? 0;
        sum += qty * price;
      }
      if (sum <= 0) return true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> _ensureOutslipDetail(
    ApiClient api,
    Map<String, dynamic> outslip,
  ) async {
    if (!_outslipDetailNeedsRefresh(outslip)) return outslip;

    final ref = _documentRef(outslip);
    if (ref.isEmpty) return outslip;

    try {
      final response = await api.request('GET', '/outslips/${Uri.encodeComponent(ref)}');
      if (response is Map && response['data'] is Map) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
    } catch (_) {}

    try {
      final rows = (await api.getList('/outslips')).cast<Map<String, dynamic>>();
      for (final row in rows) {
        if (_documentRef(row) == ref || row['id']?.toString() == outslip['id']?.toString()) {
          return Map<String, dynamic>.from(row);
        }
      }
    } catch (_) {}

    return outslip;
  }
}
