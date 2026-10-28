import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_letterhead.dart';

/// Shared PDF layout matching web `.quotation-print` styles in `frontend/src/index.css`.
class DocumentPdfLayout {
  DocumentPdfLayout._();

  static const pageFormat = PdfPageFormat.a4;
  static const margin = pw.EdgeInsets.fromLTRB(34, 28, 34, 34);

  static final money = NumberFormat('#,##0.00', 'en_PH');
  static const greenHeader = PdfColor.fromInt(0xFFC6E0B4);
  static const grayHeader = PdfColor.fromInt(0xFFD9D9D9);
  static const blueBar = PdfColor.fromInt(0xFFD9E8F7);

  static pw.TextStyle get body => const pw.TextStyle(fontSize: 11);
  static pw.TextStyle get bodyBold => const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);
  static pw.TextStyle get title => const pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold);
  static pw.TextStyle get small => const pw.TextStyle(fontSize: 10);
  static pw.TextStyle get tiny => const pw.TextStyle(fontSize: 9);

  static String formatMoney(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
    if (amount < 0) return '(${money.format(amount.abs())})';
    return money.format(amount);
  }

  static String itemNumber(int index) => '${index + 1}.0';

  static pw.Widget letterhead(pw.MemoryImage logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Image(logo, width: 72, height: 72),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(CompanyLetterhead.name, style: bodyBold.copyWith(fontSize: 13)),
              pw.SizedBox(height: 4),
              pw.Text(CompanyLetterhead.address, style: body),
              pw.Text(CompanyLetterhead.phone, style: body),
              pw.Text(CompanyLetterhead.tin, style: body),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget doubleRule() {
    return pw.Column(
      children: [
        pw.Container(height: 1.5, color: PdfColors.black),
        pw.SizedBox(height: 2),
        pw.Container(height: 1.5, color: PdfColors.black),
      ],
    );
  }

  static pw.Widget singleRule() => pw.Container(height: 1, color: PdfColors.black);

  static pw.Widget centeredTitle(String text) {
    return pw.Center(
      child: pw.Text(text, style: title, textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget fieldLine(String label, String? value, {double labelWidth = 92}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: labelWidth,
            child: pw.Text(label, style: bodyBold),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
              ),
              child: pw.Text(value?.trim().isNotEmpty == true ? value!.trim() : ' ', style: body),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget subjectLine(String? subject) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(width: 64, child: pw.Text('Subject :', style: bodyBold)),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
              ),
              child: pw.Text(subject ?? '', style: body),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget referenceBar(String label, String? value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: blueBar,
      child: pw.Row(
        children: [
          pw.SizedBox(width: 72, child: pw.Text(label, style: bodyBold)),
          pw.Expanded(child: pw.Text(value?.trim().isNotEmpty == true ? value!.trim() : ' ', style: bodyBold)),
        ],
      ),
    );
  }

  static pw.Widget sectionLabel(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(text, style: bodyBold),
    );
  }

  static pw.TableBorder get tableBorder => pw.TableBorder.all(color: PdfColors.black, width: 0.5);

  static pw.TableBorder get tableBorderNoBottom => const pw.TableBorder(
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        top: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      );

  static pw.TableBorder get tableBorderNoTop => const pw.TableBorder(
        left: pw.BorderSide(color: PdfColors.black, width: 0.5),
        right: pw.BorderSide(color: PdfColors.black, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
        horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
        verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
      );

  static pw.Widget quotationFooter({
    required String conformeName,
    required String conformeHint,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 28),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _signatureColumn(
            opening: 'Very truly yours,',
            name: CompanyLetterhead.signatoryName,
            title: CompanyLetterhead.signatoryTitle,
            showDate: true,
          )),
          pw.SizedBox(width: 40),
          pw.Expanded(child: _signatureColumn(
            label: 'CONFORME:',
            name: conformeName,
            hint: conformeHint,
            underlineName: true,
            showDate: true,
          )),
        ],
      ),
    );
  }

  static pw.Widget deliveredFooter() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 24),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _signatureColumn(
            label: 'Delivered by:',
            name: CompanyLetterhead.signatoryName,
            title: CompanyLetterhead.signatoryTitle,
          )),
          pw.SizedBox(width: 40),
          pw.Expanded(child: _signatureColumn(
            label: 'Received by:',
            hint: 'Signature Over Printed Name',
          )),
        ],
      ),
    );
  }

  static pw.Widget gatePassFooterQuad({
    required String preparedBy,
    required String authorizedBy,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 24),
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _signatureColumn(
                label: 'Prepared By:',
                name: preparedBy,
                underlineName: true,
              )),
              pw.SizedBox(width: 24),
              pw.Expanded(child: _signatureColumn(
                label: 'Authorized By:',
                name: authorizedBy,
                underlineName: true,
              )),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _signatureColumn(
                label: 'Guard on Duty:',
                hint: 'Name / Position',
              )),
              pw.SizedBox(width: 24),
              pw.Expanded(child: _signatureColumn(
                label: 'Driver:',
                hint: 'Signature Over Printed Name',
              )),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget gatePassFooter({String? exitAt}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 24),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _signatureColumn(
            label: 'Prepared by:',
            hint: 'Signature Over Printed Name',
            showDate: true,
          )),
          pw.SizedBox(width: 40),
          pw.Expanded(child: _signatureColumn(
            label: 'Authorized by:',
            hint: exitAt != null && exitAt.isNotEmpty
                ? 'Exited: $exitAt'
                : 'Signature Over Printed Name',
            showDate: exitAt == null || exitAt.isEmpty,
          )),
        ],
      ),
    );
  }

  static pw.Widget soaFooter() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 24),
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _signatureColumn(
                label: 'Prepared by:',
                name: 'Larke Gelbolingo',
                title: 'Project Manager',
              )),
              pw.SizedBox(width: 40),
              pw.Expanded(child: _signatureColumn(
                label: 'Received by:',
                hint: 'Signature Over Printed Name',
              )),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text('Thank You For Your Business!', style: body.copyWith(fontStyle: pw.FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  static pw.Widget grandTotal(double total) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.black),
          right: pw.BorderSide(color: PdfColors.black),
          bottom: pw.BorderSide(color: PdfColors.black),
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('GRAND TOTAL', style: bodyBold.copyWith(fontSize: 12)),
          pw.SizedBox(width: 24),
          pw.Container(
            width: 110,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(bottom: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 3)),
            ),
            child: pw.Text(formatMoney(total), style: bodyBold.copyWith(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static pw.Widget buildQuotationTable({
    required List<Map<String, dynamic>> items,
    required PdfColor headerColor,
    int minRows = 10,
  }) {
    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final price = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      rows.add([
        itemNumber(i),
        item['productName']?.toString() ?? item['name']?.toString() ?? '',
        qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString(),
        item['unit']?.toString() ?? 'PC/S',
        formatMoney(price),
        formatMoney(qty * price),
      ]);
    }
    return _itemsTable(
      headers: const ['Item Number', 'Item Description', 'QTY.', 'Unit', 'Unit Cost', 'Amount'],
      rows: rows,
      headerColor: headerColor,
      minRows: minRows,
      flex: const [1.1, 4.4, 0.8, 1.0, 1.3, 1.4],
      alignRight: const [false, false, true, true, true, true],
    );
  }

  static pw.Widget buildDeliveryTable({
    required List<Map<String, dynamic>> items,
    required double total,
    int minRows = 8,
  }) {
    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final price = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final brandSerial = item['brandSerial']?.toString() ??
          (item['serialNumbers'] is List
              ? (item['serialNumbers'] as List).join(', ')
              : item['brand']?.toString() ?? '');
      rows.add([
        '${i + 1}',
        item['productName']?.toString() ?? item['description']?.toString() ?? '',
        brandSerial,
        qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString(),
        item['unit']?.toString() ?? 'UNITS',
        formatMoney(price),
        formatMoney(qty * price),
      ]);
    }

    return pw.Column(
      children: [
        _itemsTable(
          headers: const ['NO', 'ITEM DESCRIPTION', 'BRAND/SERIAL NO.', 'QTY.', 'UNIT', 'Unit Price', 'Total'],
          rows: rows,
          headerColor: grayHeader,
          minRows: minRows,
          flex: const [0.5, 2.4, 2.8, 0.6, 0.8, 1.3, 1.6],
          alignRight: const [true, false, false, true, true, true, true],
          serialColumn: 2,
          nothingFollowsItalic: true,
          footerRows: [
            _footerRow([
              const _FooterCell('', colSpan: 5),
              const _FooterCell('TOTAL AMOUNT', align: pw.TextAlign.right, background: grayHeader, bold: true),
              _FooterCell(formatMoney(total), align: pw.TextAlign.right, bold: true, doubleUnderline: true),
            ]),
          ],
        ),
      ],
    );
  }

  static pw.Widget buildGatePassTable({
    required List<Map<String, dynamic>> items,
    int minRows = 6,
  }) {
    String dash(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? '—' : text;
    }

    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final name = item['productName']?.toString() ?? item['name']?.toString() ?? '';
      final code = item['productCode']?.toString() ?? '';
      final description = code.isEmpty ? name : '$name\n$code';
      rows.add([
        '${i + 1}',
        description,
        dash(item['brand']?.toString()),
        dash(item['model']?.toString()),
        qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString(),
        item['unit']?.toString() ?? 'UNIT',
      ]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Items to Leave Premises', style: bodyBold),
        pw.SizedBox(height: 6),
        _itemsTable(
          headers: const ['No.', 'Item Description', 'Brand', 'Model / Serial No.', 'Qty', 'Unit'],
          rows: rows,
          headerColor: grayHeader,
          minRows: minRows,
          flex: const [0.5, 3.2, 1.0, 1.2, 0.7, 0.8],
          alignRight: const [true, false, true, true, true, true],
          nothingFollowsItalic: true,
        ),
      ],
    );
  }

  static pw.Widget buildSoaTable({
    required List<Map<String, dynamic>> debitRows,
    required double totalAmount,
    required double paymentsApplied,
    required double balanceDue,
    int minRows = 12,
  }) {
    final rows = <List<String>>[];
    for (var i = 0; i < debitRows.length; i++) {
      final row = debitRows[i];
      final debit = (row['debit'] as num?)?.toDouble() ?? 0;
      rows.add([
        '${i + 1}',
        '1',
        'LOT',
        row['description']?.toString() ?? row['ref']?.toString() ?? '',
        formatMoney(debit),
        formatMoney(debit),
      ]);
    }

    final footerRows = <pw.TableRow>[
      _footerRow([
        const _FooterCell('', colSpan: 3),
        const _FooterCell('TOTAL AMOUNT', align: pw.TextAlign.right, background: blueBar, bold: true),
        const _FooterCell('PHP', align: pw.TextAlign.center, background: blueBar, bold: true),
        _FooterCell(formatMoney(totalAmount), align: pw.TextAlign.right, background: blueBar, bold: true),
      ]),
    ];
    if (paymentsApplied > 0) {
      footerRows.addAll([
        _footerRow([
          const _FooterCell('', colSpan: 3),
          const _FooterCell('Less: Payments', align: pw.TextAlign.right, background: blueBar, bold: true),
          const _FooterCell('PHP', align: pw.TextAlign.center, background: blueBar, bold: true),
          _FooterCell(formatMoney(paymentsApplied), align: pw.TextAlign.right, background: blueBar, bold: true),
        ]),
        _footerRow([
          const _FooterCell('', colSpan: 3),
          const _FooterCell('Balance Due', align: pw.TextAlign.right, background: blueBar, bold: true),
          const _FooterCell('PHP', align: pw.TextAlign.center, background: blueBar, bold: true),
          _FooterCell(formatMoney(balanceDue), align: pw.TextAlign.right, background: blueBar, bold: true),
        ]),
      ]);
    }

    return _itemsTable(
      headers: const ['ITEM', 'QTY', 'UNIT', 'ITEM DESCRIPTION', 'UNIT PRICE', 'TOTAL'],
      rows: rows,
      headerColor: grayHeader,
      minRows: minRows,
      flex: const [0.7, 0.7, 0.9, 3.0, 1.3, 1.4],
      alignRight: const [true, true, true, false, true, true],
      nothingFollowsItalic: true,
      footerRows: footerRows,
    );
  }

  static pw.Widget _itemsTable({
    required List<String> headers,
    required List<List<String>> rows,
    required PdfColor headerColor,
    required int minRows,
    required List<double> flex,
    required List<bool> alignRight,
    int? serialColumn,
    bool nothingFollowsItalic = false,
    List<pw.TableRow>? footerRows,
  }) {
    final columnWidths = {
      for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i]),
    };

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerColor),
        children: [
          for (var i = 0; i < headers.length; i++)
            _cell(headers[i], align: pw.TextAlign.center, bold: true, fontSize: serialColumn == null ? 10 : (i == serialColumn ? 9 : 10)),
        ],
      ),
      for (final row in rows)
        pw.TableRow(
          children: [
            for (var i = 0; i < row.length; i++)
              _cell(
                row[i],
                align: alignRight[i] ? pw.TextAlign.right : pw.TextAlign.left,
                fontSize: serialColumn == i ? 9 : 10,
              ),
          ],
        ),
      for (var i = 0; i < (minRows - rows.length).clamp(0, minRows); i++)
        pw.TableRow(
          children: List.generate(headers.length, (_) => _cell(' ')),
        ),
    ];

    final hasFooter = footerRows != null && footerRows.isNotEmpty;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(
          border: tableBorderNoBottom,
          columnWidths: columnWidths,
          children: tableRows,
        ),
        _nothingFollowsBar(italic: nothingFollowsItalic, includeBottom: !hasFooter),
        if (hasFooter)
          pw.Table(
            border: tableBorderNoTop,
            columnWidths: columnWidths,
            children: footerRows,
          ),
      ],
    );
  }

  static pw.Widget _nothingFollowsBar({bool italic = false, bool includeBottom = true}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: const pw.BorderSide(color: PdfColors.black, width: 0.5),
          right: const pw.BorderSide(color: PdfColors.black, width: 0.5),
          bottom: includeBottom ? const pw.BorderSide(color: PdfColors.black, width: 0.5) : pw.BorderSide.none,
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      alignment: pw.Alignment.center,
      child: pw.Text(
        '****NOTHING FOLLOWS****',
        textAlign: pw.TextAlign.center,
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static pw.Widget _signatureColumn({
    String? opening,
    String? label,
    String name = '',
    String? title,
    String? hint,
    bool underlineName = false,
    bool showDate = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (opening != null) pw.Text(opening, style: body),
        if (label != null) pw.Text(label, style: bodyBold),
        pw.SizedBox(height: 48),
        if (name.isNotEmpty)
          pw.Text(
            name.toUpperCase(),
            style: bodyBold.copyWith(
              decoration: underlineName ? pw.TextDecoration.underline : null,
            ),
          ),
        if (title != null) pw.Text(title.toUpperCase(), style: body),
        if (hint != null) pw.Text(hint, style: small),
        if (showDate)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Date:', style: body),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Container(
                    height: 14,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
    bool italic = false,
    double fontSize = 10,
    PdfColor? background,
    bool doubleUnderline = false,
  }) {
    return pw.Container(
      color: background,
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          decoration: doubleUnderline ? pw.TextDecoration.underline : null,
          decorationStyle: doubleUnderline ? pw.TextDecorationStyle.double : null,
        ),
      ),
    );
  }

  static pw.TableRow _footerRow(List<_FooterCell> cells) {
    final widgets = <pw.Widget>[];
    for (final cell in cells) {
      if (cell.colSpan > 1) {
        for (var i = 0; i < cell.colSpan; i++) {
          widgets.add(_cell(
            i == 0 ? cell.text : '',
            align: cell.align,
            bold: cell.bold,
            background: cell.background,
            doubleUnderline: cell.doubleUnderline,
          ));
        }
      } else {
        widgets.add(_cell(
          cell.text,
          align: cell.align,
          bold: cell.bold,
          background: cell.background,
          doubleUnderline: cell.doubleUnderline,
        ));
      }
    }
    return pw.TableRow(children: widgets);
  }
}

class _FooterCell {
  const _FooterCell(
    this.text, {
    this.colSpan = 1,
    this.align = pw.TextAlign.left,
    this.bold = false,
    this.background,
    this.doubleUnderline = false,
  });

  final String text;
  final int colSpan;
  final pw.TextAlign align;
  final bool bold;
  final PdfColor? background;
  final bool doubleUnderline;
}
