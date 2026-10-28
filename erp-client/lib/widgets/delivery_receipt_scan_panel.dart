import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/transaction_actions.dart';
import '../theme/app_theme.dart';
import 'barcode_camera_scan_page.dart';
import 'field_ui.dart';
import 'print_document_button.dart';
import 'transaction_workflows.dart';

List<Map<String, dynamic>> cloneDeliveryItems(List<Map<String, dynamic>> items) {
  return items
      .map(
        (item) => {
          ...item,
          'serialNumbers': (item['serialNumbers'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
        },
      )
      .toList();
}

/// Full delivery-receipt detail layout when serial scanning is active.
class DeliveryScanDetailView extends StatefulWidget {
  const DeliveryScanDetailView({
    super.key,
    required this.api,
    required this.delivery,
    required this.onSaved,
    this.popAfterMutations = true,
    this.onSetStatus,
    this.onCreateBilling,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
    this.offline = false,
    this.onCloseScan,
  });

  final ApiClient api;
  final Map<String, dynamic> delivery;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final bool popAfterMutations;
  final Future<void> Function(String status)? onSetStatus;
  final Future<void> Function()? onCreateBilling;
  final String? workflowNotice;
  final bool workflowNoticeLoading;
  final bool offline;
  final VoidCallback? onCloseScan;

  @override
  State<DeliveryScanDetailView> createState() => _DeliveryScanDetailViewState();
}

class _DeliveryScanDetailViewState extends State<DeliveryScanDetailView> {
  static const _bottomBarHeight = 88.0;

  late List<Map<String, dynamic>> _items;
  late Map<String, dynamic> _delivery;
  final _productController = TextEditingController();
  final _serialController = TextEditingController();
  final _serialFocus = FocusNode();
  int _activeIndex = 0;
  bool _saving = false;
  bool _loadingDetail = false;
  String? _error;
  bool _manualEntryExpanded = false;

  @override
  void initState() {
    super.initState();
    _applyDelivery(widget.delivery);
    if (!widget.offline) {
      _reloadDeliveryDetail(silent: true);
    }
  }

  @override
  void didUpdateWidget(covariant DeliveryScanDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delivery != widget.delivery) {
      _applyDelivery(widget.delivery);
      if (!widget.offline && deliveryRecordNeedsDetailRefresh(_delivery)) {
        _reloadDeliveryDetail(silent: true);
      }
    }
  }

  void _applyDelivery(Map<String, dynamic> delivery) {
    _delivery = Map<String, dynamic>.from(delivery);
    _items = cloneDeliveryItems(deliveryLineItems(_delivery));
    _syncActiveIndex();
  }

  void _syncActiveIndex() {
    if (_items.isEmpty) {
      _activeIndex = 0;
      return;
    }
    for (var index = 0; index < _items.length; index++) {
      if (!deliveryLineSerialProgress(_items[index]).complete) {
        _activeIndex = index;
        return;
      }
    }
    _activeIndex = 0;
  }

  Future<void> _reloadDeliveryDetail({bool silent = false}) async {
    if (widget.offline || _loadingDetail) return;
    final id = _delivery['dbId'] ?? _delivery['id'];
    if (id == null) return;

    if (!silent) {
      setState(() {
        _loadingDetail = true;
        _error = null;
      });
    } else if (deliveryRecordNeedsDetailRefresh(_delivery)) {
      setState(() => _loadingDetail = true);
    } else {
      return;
    }

    try {
      final data = await fetchDeliveryDetailRecord(widget.api, _delivery);
      if (!mounted) return;
      setState(() {
        _applyDelivery(data);
        _loadingDetail = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        if (!silent) _error = friendlyApiError(error);
      });
    }
  }

  @override
  void dispose() {
    _productController.dispose();
    _serialController.dispose();
    _serialFocus.dispose();
    super.dispose();
  }

  bool get _disabled => widget.offline || _saving;

  Map<String, dynamic>? get _activeLine =>
      _items.isEmpty ? null : _items[_activeIndex.clamp(0, _items.length - 1)];

  void _applyLocalItems(List<Map<String, dynamic>> nextItems) {
    _items = cloneDeliveryItems(nextItems);
    _delivery = {..._delivery, 'items': nextItems};
  }

  Future<void> _persistItems(List<Map<String, dynamic>> nextItems) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await updateDeliverySerials(widget.api, _delivery, nextItems);
      if (!mounted) return;
      if (updated == null) {
        setState(() {
          _items = cloneDeliveryItems(deliveryLineItems(_delivery));
          _error = 'Could not save serial numbers.';
        });
        return;
      }
      final savedItems = (updated['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final merged = Map<String, dynamic>.from(updated);
      if (savedItems.isNotEmpty) {
        merged['items'] = savedItems;
      } else {
        merged['items'] = nextItems;
      }
      setState(() {
        _delivery = merged;
        _items = cloneDeliveryItems(deliveryLineItems(merged));
      });
      widget.onSaved(merged);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items = cloneDeliveryItems(deliveryLineItems(_delivery));
        _error = error is FormatException
            ? error.message
            : friendlyApiError(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectProductWithCode(String code) async {
    if (_disabled) return;
    if (code.isEmpty) return;

    final formatError = validateDeliveryProductBarcode(code);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }

    try {
      final item = await fetchSetupItemByBarcode(widget.api, code);
      if (!mounted) return;
      if (item == null) {
        setState(() => _error = 'Barcode not found.');
        return;
      }

      final index = _items.indexWhere(
        (line) => line['productId']?.toString() == item['id']?.toString(),
      );
      if (index < 0) {
        setState(
          () => _error = '${item['name'] ?? 'Item'} is not on this delivery receipt.',
        );
        return;
      }

      setState(() {
        _activeIndex = index;
        _error = null;
        _productController.clear();
      });
      _serialFocus.requestFocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyApiError(error));
    }
  }

  String? _validateUnifiedScanCode(String code) {
    final trimmed = code.trim();
    if (trimmed.length < 3) return 'Hold steady — code looks too short.';
    if (trimmed.length > 128) return 'Code is too long.';
    return null;
  }

  /// If [code] is a setup product barcode on this DR, selects the line and returns a result.
  /// Returns null when the code should be treated as a serial sticker.
  Future<BarcodeContinuousScanResult?> _tryUnifiedProductBarcode(String code) async {
    final formatError = validateDeliveryProductBarcode(code);
    if (formatError != null) return null;

    try {
      final item = await fetchSetupItemByBarcode(widget.api, code);
      if (item == null) return null;

      final index = _items.indexWhere(
        (line) => line['productId']?.toString() == item['id']?.toString(),
      );
      if (index < 0) {
        return BarcodeContinuousScanResult.error(
          '${item['name'] ?? 'Item'} is not on this delivery.',
        );
      }

      if (!mounted) return BarcodeContinuousScanResult.keepOpen;
      setState(() {
        _activeIndex = index;
        _error = null;
        _productController.clear();
      });

      final name = item['name']?.toString() ?? 'Item';
      final progress = deliveryLineSerialProgress(_items[index]);
      if (progress.complete) {
        return BarcodeContinuousScanResult.ok(
          'Product line: $name (serials already complete). Scan next product or serial.',
        );
      }
      return BarcodeContinuousScanResult.ok('Product: $name — scan unit serial sticker(s) next.');
    } catch (error) {
      return BarcodeContinuousScanResult.error(friendlyApiError(error));
    }
  }

  Future<BarcodeContinuousScanResult> _handleUnifiedScan(String code) async {
    final productResult = await _tryUnifiedProductBarcode(code);
    if (productResult != null) return productResult;
    return _addSerialWithCode(code);
  }

  Future<void> _openUnifiedScanner() async {
    if (_disabled) return;

    final overall = deliveryOverallSerialProgress({..._delivery, 'items': _items});
    if (overall.complete) {
      setState(() => _error = 'All serial numbers are already captured for this delivery.');
      return;
    }

    setState(() => _error = null);
    await BarcodeCameraScanPage.scanContinuous(
      context,
      title: 'Scan',
      hint: 'Box/packaging barcode = product line · Sticker on unit = serial.',
      validate: _validateUnifiedScanCode,
      onScan: _handleUnifiedScan,
    );
  }

  int _resolveSerialLineIndex() {
    final active = _activeLine;
    if (active != null && !deliveryLineSerialProgress(active).complete) {
      return _activeIndex;
    }
    for (var index = 0; index < _items.length; index++) {
      if (!deliveryLineSerialProgress(_items[index]).complete) {
        return index;
      }
    }
    return -1;
  }

  Future<BarcodeContinuousScanResult> _addSerialWithCode(String serial) async {
    if (_disabled) return BarcodeContinuousScanResult.keepOpen;

    if (serial.isEmpty) return BarcodeContinuousScanResult.keepOpen;

    final formatError = validateDeliverySerialNumber(serial);
    if (formatError != null) {
      setState(() => _error = formatError);
      return BarcodeContinuousScanResult.error(formatError);
    }

    if (deliverySerialAlreadyUsed(_items, serial)) {
      const message = 'This serial was already scanned on this delivery.';
      setState(() => _error = message);
      return BarcodeContinuousScanResult.error(message);
    }

    final lineIndex = _resolveSerialLineIndex();
    if (lineIndex < 0) {
      const message = 'All serial numbers are already captured.';
      setState(() {
        _error = message;
        _serialController.clear();
      });
      return BarcodeContinuousScanResult.error(message);
    }

    final line = _items[lineIndex];
    final progress = deliveryLineSerialProgress(line);
    if (progress.complete) {
      final message = '${line['productName'] ?? 'Item'} already has all serial numbers captured.';
      setState(() {
        _error = message;
        _serialController.clear();
      });
      return BarcodeContinuousScanResult.error(message);
    }

    setState(() => _activeIndex = lineIndex);

    final nextItems = _items.asMap().entries.map((entry) {
      if (entry.key != lineIndex) return entry.value;
      final serials = [
        ...(entry.value['serialNumbers'] as List<dynamic>? ?? const [])
            .map((value) => value.toString()),
        serial,
      ];
      return {...entry.value, 'serialNumbers': serials};
    }).toList();

    setState(() {
      _applyLocalItems(nextItems);
      _serialController.clear();
      _error = null;
    });
    await _persistItems(nextItems);
    if (!mounted) return BarcodeContinuousScanResult.keepOpen;
    _serialFocus.requestFocus();

    if (_error != null) {
      return BarcodeContinuousScanResult.error(_error!);
    }

    final overall = deliveryOverallSerialProgress({..._delivery, 'items': _items});
    if (overall.complete) {
      return BarcodeContinuousScanResult.ok('All serials captured. Tap Done to close.');
    }

    final updatedLine = _activeLine;
    final name = updatedLine?['productName']?.toString() ?? 'Item';
    return BarcodeContinuousScanResult.ok('Serial saved for $name.');
  }

  Future<void> _removeSerial(int lineIndex, int serialIndex) async {
    if (_disabled) return;

    final nextItems = _items.asMap().entries.map((entry) {
      if (entry.key != lineIndex) return entry.value;
      final serials = [
        ...(entry.value['serialNumbers'] as List<dynamic>? ?? const [])
            .map((value) => value.toString()),
      ];
      if (serialIndex >= 0 && serialIndex < serials.length) {
        serials.removeAt(serialIndex);
      }
      return {...entry.value, 'serialNumbers': serials};
    }).toList();

    setState(() => _applyLocalItems(nextItems));
    await _persistItems(nextItems);
  }

  Future<void> _setStatus(String status) async {
    final handler = widget.onSetStatus;
    if (handler == null) return;
    await handler(status);
    if (widget.popAfterMutations && mounted) Navigator.pop(context);
  }

  Widget _buildSerialTag({
    required String serial,
    required VoidCallback? onRemove,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tag_outlined, size: 14, color: AppTheme.maroon),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              serial,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null)
            TextButton(
              onPressed: onRemove,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppTheme.textSecondary,
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              child: const Text('Remove'),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final overall = deliveryOverallSerialProgress({..._delivery, 'items': _items});
    final fraction = overall.needed <= 0
        ? 0.0
        : (overall.captured / overall.needed).clamp(0.0, 1.0);

    return Card(
      color: AppTheme.maroonLight,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overall.complete ? Icons.check_circle_outline : Icons.qr_code_scanner,
                  color: overall.complete ? AppTheme.successText : AppTheme.maroon,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    overall.complete
                        ? 'All serial numbers captured'
                        : '${overall.captured} of ${overall.needed} units scanned',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            if (overall.needed > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white,
                  color: overall.complete ? AppTheme.successText : AppTheme.maroon,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntry() {
    final activeLine = _activeLine;
    final activeProgress = activeLine == null ? null : deliveryLineSerialProgress(activeLine);

    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: _manualEntryExpanded,
          onExpansionChanged: (expanded) => setState(() => _manualEntryExpanded = expanded),
          leading: const Icon(Icons.keyboard_outlined, color: AppTheme.maroon, size: 22),
          title: const Text('Type instead', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'For a handheld scanner or manual entry',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            TextField(
              controller: _productController,
              enabled: !_disabled,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Product barcode',
                hintText: 'Scan or type product barcode',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (value) => _selectProductWithCode(value.trim()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serialController,
              focusNode: _serialFocus,
              enabled: !_disabled && activeLine != null,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: activeLine == null
                    ? 'Serial number'
                    : 'Serial — ${activeLine['productName'] ?? 'Item'} '
                        '(${activeProgress?.captured ?? 0}/${activeProgress?.needed ?? 0})',
                hintText: 'Scan or type serial sticker',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (value) => _addSerialWithCode(value.trim()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineCard(int index) {
    final item = _items[index];
    final progress = deliveryLineSerialProgress(item);
    final serials = (item['serialNumbers'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final active = index == _activeIndex;
    final qty = item['quantity'] ?? '—';

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: active ? AppTheme.maroon : AppTheme.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: _disabled ? null : () => setState(() => _activeIndex = index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: active
                    ? AppTheme.maroon
                    : AppTheme.maroon.withValues(alpha: 0.12),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.maroon,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['productName']?.toString() ?? 'Item',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty $qty · Serials ${progress.captured}/${progress.needed}',
                      style: TextStyle(
                        fontSize: 12,
                        color: progress.complete ? AppTheme.successText : AppTheme.textSecondary,
                      ),
                    ),
                    if (serials.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Captured serials',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < serials.length; i++)
                            _buildSerialTag(
                              serial: serials[i],
                              onRemove: _disabled ? null : () => _removeSerial(index, i),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (progress.complete)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle, color: AppTheme.successText, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildWorkflowActions() {
    final secondary = <Widget>[
      PrintDocumentButton(
        onPrint: () => printDeliveryReceipt(context, widget.api, _delivery),
        label: 'Print PDF',
        enabled: !widget.offline,
      ),
    ];
    final primary = <Widget>[
      if (widget.onSetStatus != null && canMarkDeliveryOutWithSerials(_delivery))
        FilledButton(
          onPressed: _saving ? null : () => _setStatus('out_for_delivery'),
          child: const Text('Out for delivery'),
        ),
      if (canMarkDeliveryOut(_delivery) && deliverySerialsPending(_delivery))
        Text(
          deliverySerialsBlockedMessage(),
          style: const TextStyle(color: AppTheme.warningText, height: 1.35),
        ),
      if (widget.onSetStatus != null && canMarkDeliveryDeliveredWithSerials(_delivery))
        FilledButton(
          onPressed: _saving ? null : () => _setStatus('delivered'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Mark as delivered'),
        ),
      if (widget.onCreateBilling != null)
        FilledButton(
          onPressed: _saving ? null : () => widget.onCreateBilling!(),
          child: const Text('Create billing'),
        ),
    ];

    if (secondary.isEmpty && primary.isEmpty) return null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FieldDetailActions(secondary: secondary, primary: primary),
      ),
    );
  }

  Widget _buildBottomBar() {
    final overall = deliveryOverallSerialProgress({..._delivery, 'items': _items});
    final line = _activeLine;
    final lineName = line?['productName']?.toString();

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 3, color: AppTheme.maroon),
              ),
            Text(
              overall.complete
                  ? 'All units captured — you can mark delivered when ready.'
                  : lineName == null
                      ? 'Scan the box barcode for each product, then each unit sticker.'
                      : 'Active: $lineName — scan box barcode or serial sticker.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _disabled || overall.complete ? null : _openUnifiedScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: const Text('Scan'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _delivery['status']?.toString() ?? '';
    final customer = _delivery['customerName']?.toString().isNotEmpty == true
        ? _delivery['customerName'].toString()
        : 'Customer —';
    final title = _delivery['id']?.toString() ?? 'Delivery';
    final workflowActions = _buildWorkflowActions();
    final showCaptureBar = status == 'active';
    final bottomPad = showCaptureBar ? _bottomBarHeight + 16.0 : 24.0;

    return Scaffold(
      appBar: transactionAppBar(
        context,
        title: title,
        showBack: true,
        onBack: widget.onCloseScan,
      ),
      bottomNavigationBar: showCaptureBar ? _buildBottomBar() : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          customer,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (status.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FieldStatusChip(status),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  FieldDetailMeta(
                    rows: [
                      (label: 'Date', value: '${_delivery['displayDate'] ?? _delivery['date'] ?? '—'}'),
                      (label: 'Outslip', value: '${_delivery['referenceOutslipId'] ?? '—'}'),
                      (label: 'Total', value: fieldFormatMoney(_delivery['total'])),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildProgressCard(),
          const SizedBox(height: 16),
          const FieldSectionTitle('Line items'),
          const SizedBox(height: 6),
          Text(
            'Tap a line to select it, then use Scan for the box barcode and each unit sticker.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 10),
          if (_loadingDetail && _items.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: AppTheme.maroon),
              ),
            )
          else if (_items.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.refresh, color: AppTheme.maroon),
                title: const Text('Could not load products', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Tap to reload line items from the server.'),
                onTap: _loadingDetail ? null : () => _reloadDeliveryDetail(),
              ),
            )
          else
            for (var index = 0; index < _items.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              _buildLineCard(index),
            ],
          const SizedBox(height: 14),
          _buildManualEntry(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.errorBg,
              margin: EdgeInsets.zero,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline, color: AppTheme.errorText),
                title: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.errorText, fontSize: 13, height: 1.35),
                ),
              ),
            ),
          ],
          if (widget.workflowNotice != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.maroonLight,
              child: ListTile(
                dense: true,
                leading: widget.workflowNoticeLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.maroon),
                      )
                    : const Icon(Icons.info_outline_rounded, color: AppTheme.maroon),
                title: Text(
                  widget.workflowNotice!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.35),
                ),
              ),
            ),
          ],
          if (workflowActions != null) ...[
            const SizedBox(height: 12),
            workflowActions,
          ],
        ],
      ),
    );
  }
}
