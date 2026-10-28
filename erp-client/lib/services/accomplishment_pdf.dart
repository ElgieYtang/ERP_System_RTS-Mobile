import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_letterhead.dart';

/// Printable accomplishment report — matches web `.ar-print` / office template.
class AccomplishmentPdf {
  AccomplishmentPdf._();

  static const imagesPerPage = 4;

  /// Accomplishment reports use the office address block (not quotation letterhead).
  static const _companyName = CompanyLetterhead.name;
  static const _companyAddress =
      'RM301E-3 MEDALLE BLDG. FUENTE OSMEÑA CAPITOL SITE CEBU CITY';
  static const _companyPhone = '345-2283/09175734911';
  static const _signatoryName = CompanyLetterhead.signatoryName;

  static const _pageMargin = pw.EdgeInsets.fromLTRB(34, 28, 34, 34);

  static const _border = PdfColors.black;
  static const _borderWidth = 1.0;
  static const _cellPadding = pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5);
  static const _borderSide = pw.BorderSide(color: _border, width: _borderWidth);

  static const _labelStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
  );
  static const _valueStyle = pw.TextStyle(fontSize: 9);
  static const _titleStyle = pw.TextStyle(
    fontSize: 17,
    fontWeight: pw.FontWeight.bold,
    letterSpacing: 0.5,
  );
  static const _companyNameStyle = pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    letterSpacing: 0.2,
  );
  static const _companyLineStyle = pw.TextStyle(fontSize: 7.5);

  static Future<Uint8List> build({
    required Map<String, dynamic> report,
    required Map<String, Uint8List> photoBytes,
  }) async {
    final logoData = await rootBundle.load('assets/logo.png');
    final logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    final orderedPhotos = <Uint8List>[];
    final images =
        (report['images'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    for (final image in images) {
      final id = image['id']?.toString();
      if (id != null && photoBytes.containsKey(id)) {
        orderedPhotos.add(photoBytes[id]!);
      }
    }

    final pageCount = orderedPhotos.isEmpty
        ? 1
        : (orderedPhotos.length / imagesPerPage).ceil();
    final doc = pw.Document();

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final isFirstPage = pageIndex == 0;
      final isLastPage = pageIndex == pageCount - 1;
      final start = pageIndex * imagesPerPage;
      final slice = orderedPhotos.skip(start).take(imagesPerPage).toList();
      while (slice.length < imagesPerPage) {
        slice.add(Uint8List(0));
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: _pageMargin,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (isFirstPage)
                  _letterhead(logoImage)
                else
                  _continuedHeader(pageIndex + 1, pageCount),
                if (isFirstPage) _infoTable(report),
                pw.Expanded(
                  child: _picturesSection(
                    slice,
                    attached: isFirstPage,
                  ),
                ),
                if (isLastPage) ...[
                  pw.SizedBox(height: 14),
                  _signatureSection(report),
                ],
              ],
            );
          },
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _letterhead(pw.MemoryImage logo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Image(logo, width: 51, height: 51),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _companyName,
                    style: _companyNameStyle,
                  ),
                  pw.Text(
                    _companyAddress,
                    style: _companyLineStyle,
                  ),
                  pw.Text(
                    _companyPhone,
                    style: _companyLineStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Text(
            'ACCOMPLISHMENT REPORT',
            style: _titleStyle,
          ),
        ),
        pw.SizedBox(height: 11),
      ],
    );
  }

  static pw.Widget _continuedHeader(int page, int total) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'ACCOMPLISHMENT REPORT',
            style: _titleStyle,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page $page of $total',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ),
        pw.SizedBox(height: 11),
      ],
    );
  }

  static pw.Widget _infoTable(Map<String, dynamic> report) {
    String text(String? value) => (value == null || value.isEmpty) ? ' ' : value;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: _borderWidth),
      ),
      child: pw.Column(
        children: [
          _infoRow(
            cells: [
              _InfoCell(11, _tableLabel('Project Name:')),
              _InfoCell(39, _tableValue(text(report['projectName']?.toString()))),
            ],
            drawBottom: true,
          ),
          _infoRow(
            cells: [
              _InfoCell(11, _tableLabel('Location')),
              _InfoCell(14, _tableValue(text(report['location']?.toString()))),
              _InfoCell(11, _tableLabel('Remarks')),
              _InfoCell(14, _tableValue(text(report['remarks']?.toString()))),
            ],
            drawBottom: true,
          ),
          _infoRow(
            cells: [
              _InfoCell(11, _tableLabel('Installation Report No:')),
              _InfoCell(
                14,
                _tableValue(
                  text(
                    report['installationReportNo']?.toString() ??
                        report['id']?.toString(),
                  ),
                ),
              ),
              _InfoCell(11, _tableLabel('Date:')),
              _InfoCell(
                14,
                _tableValue(
                  text(report['displayDate']?.toString() ?? report['date']?.toString()),
                ),
              ),
            ],
            drawBottom: false,
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow({
    required List<_InfoCell> cells,
    required bool drawBottom,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: drawBottom ? _borderSide : pw.BorderSide.none,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            pw.Expanded(
              flex: cells[i].flex,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    right: i < cells.length - 1 ? _borderSide : pw.BorderSide.none,
                  ),
                ),
                padding: _cellPadding,
                child: cells[i].child,
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _tableLabel(String text) {
    return pw.Text(text, style: _labelStyle);
  }

  static pw.Widget _tableValue(String text) {
    return pw.Text(text, style: _valueStyle);
  }

  static pw.Widget _picturesSection(List<Uint8List> slots, {required bool attached}) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: const pw.BorderSide(color: _border, width: _borderWidth),
          right: const pw.BorderSide(color: _border, width: _borderWidth),
          bottom: const pw.BorderSide(color: _border, width: _borderWidth),
          top: attached
              ? pw.BorderSide.none
              : const pw.BorderSide(color: _border, width: _borderWidth),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _border, width: _borderWidth),
              ),
            ),
            child: pw.Text('Pictures', style: _labelStyle),
          ),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Expanded(child: _photoCell(slots[0], right: true, bottom: true)),
                      pw.Expanded(child: _photoCell(slots[1], bottom: true)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Expanded(child: _photoCell(slots[2], right: true)),
                      pw.Expanded(child: _photoCell(slots[3])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _photoCell(
    Uint8List bytes, {
    bool right = false,
    bool bottom = false,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          right: right
              ? const pw.BorderSide(color: _border, width: _borderWidth)
              : pw.BorderSide.none,
          bottom: bottom
              ? const pw.BorderSide(color: _border, width: _borderWidth)
              : pw.BorderSide.none,
        ),
      ),
      padding: const pw.EdgeInsets.all(3),
      child: bytes.isEmpty
          ? pw.SizedBox.expand()
          : pw.Center(
              child: pw.Image(
                pw.MemoryImage(bytes),
                fit: pw.BoxFit.contain,
              ),
            ),
    );
  }

  static pw.Widget _signatureSection(Map<String, dynamic> report) {
    final preparedByPosition =
        report['preparedByPosition']?.toString() ?? CompanyLetterhead.signatoryTitle;
    final confirmedByLabel = report['confirmedByLabel']?.toString() ??
        'SIGNATURE OF PRINTED NAME/POSITION';

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: _borderWidth),
      columnWidths: {
        0: const pw.FlexColumnWidth(),
        1: const pw.FlexColumnWidth(),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        pw.TableRow(
          children: [
            _sigHeader('Prepared By:'),
            _sigHeader('Confirmed By:'),
          ],
        ),
        pw.TableRow(
          children: [
            _sigBody(_signatoryName, preparedByPosition),
            _sigBodyLabel(confirmedByLabel),
          ],
        ),
      ],
    );
  }

  static pw.Widget _sigHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: pw.Text(text, style: _labelStyle),
    );
  }

  static pw.Widget _sigBody(String name, String role) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 40),
          pw.Text(
            name.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
              decorationThickness: 0.75,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            role.toUpperCase(),
            style: const pw.TextStyle(fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sigBodyLabel(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(height: 40),
          pw.Text(
            label.toUpperCase(),
            style: _labelStyle.copyWith(fontSize: 7.5),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InfoCell {
  const _InfoCell(this.flex, this.child);

  final int flex;
  final pw.Widget child;
}
