import 'package:flutter/material.dart';

import '../navigation/app_navigation.dart';
import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../services/transaction_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';
import '../widgets/transaction_workflows.dart';

class GatePassPage extends StatefulWidget {
  const GatePassPage({
    super.key,
    required this.api,
    required this.outslip,
    this.offline = false,
  });

  /// Shown when gate pass was never loaded while online.
  static const offlineLoadMessage =
      'Connect to the internet to load this gate pass for the first time.';

  final ApiClient api;
  final Map<String, dynamic> outslip;
  final bool offline;

  @override
  State<GatePassPage> createState() => _GatePassPageState();
}

class _GatePassPageState extends State<GatePassPage> {
  static const _bottomBarHeight = 132.0;

  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  String? _offlineLabel;
  Map<String, dynamic>? _document;
  Map<String, dynamic>? _savedFormSnapshot;

  final _destinationController = TextEditingController();
  final _driverController = TextEditingController();
  final _plateController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _remarksController = TextEditingController();

  static const _fieldDecoration = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(),
  );

  @override
  void initState() {
    super.initState();
    _loadOfflineLabel();
    _load();
  }

  Future<void> _loadOfflineLabel() async {
    if (!widget.offline) return;
    final cached = await OfflineCache.loadList(OfflineCache.outslips);
    if (!mounted) return;
    setState(() => _offlineLabel = OfflineCache.staleLabel(cached.savedAt));
  }

  String get _offlineBannerLabel =>
      _offlineLabel ?? OfflineCache.staleLabel(null);

  @override
  void dispose() {
    _destinationController.dispose();
    _driverController.dispose();
    _plateController.dispose();
    _vehicleController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _formPayload() => buildGatePassPayload(
        destination: _destinationController.text,
        driverName: _driverController.text,
        plateNo: _plateController.text,
        vehicleNo: _vehicleController.text,
        remarks: _remarksController.text,
      );

  Map<String, dynamic> _mergedDocument() {
    if (_document == null) return {};
    return mergeGatePassDocument(_document!, _formPayload());
  }

  bool get _canEdit =>
      _document != null && canEditGatePass(_document!, offline: widget.offline);

  bool get _canMarkExited =>
      _document != null && canMarkGatePassExited(_document!, offline: widget.offline);

  bool get _hasUnsavedChanges {
    if (!_canEdit || _savedFormSnapshot == null) return false;
    final current = _formPayload();
    for (final entry in _savedFormSnapshot!.entries) {
      if (current[entry.key] != entry.value) return true;
    }
    return false;
  }

  Future<bool> _confirmDiscardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text('Your gate pass edits have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    return _confirmDiscardChanges();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    final ref = fieldDbId(widget.outslip);

    if (widget.offline && ref.isNotEmpty) {
      final cached = await OfflineCache.loadGatePass(ref);
      if (cached.data != null && mounted) {
        setState(() {
          _applyDocument(cached.data!);
          _offlineLabel = OfflineCache.staleLabel(cached.savedAt);
        });
        setState(() => _loading = false);
        return;
      }
    }

    try {
      final document = await fetchGatePassDocument(widget.api, widget.outslip);
      if (ref.isNotEmpty) {
        await OfflineCache.saveGatePass(ref, document);
      }
      if (!mounted) return;
      setState(() => _applyDocument(document));
    } catch (error) {
      if (ref.isNotEmpty) {
        final cached = await OfflineCache.loadGatePass(ref);
        if (cached.data != null && mounted) {
          setState(() {
            _applyDocument(cached.data!);
            if (widget.offline) {
              _offlineLabel = OfflineCache.staleLabel(cached.savedAt);
            }
          });
          return;
        }
      }
      if (mounted) {
        setState(() {
          _document = null;
          _loadError = widget.offline
              ? GatePassPage.offlineLoadMessage
              : friendlyApiError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistDocumentCache(Map<String, dynamic> document) async {
    final ref = fieldDbId(widget.outslip);
    if (ref.isEmpty) return;
    await OfflineCache.saveGatePass(ref, document);
  }

  void _applyDocument(Map<String, dynamic> document) {
    _document = document;
    _destinationController.text = document['destination']?.toString() ?? '';
    _driverController.text = document['driverName']?.toString() ?? '';
    _plateController.text = document['plateNo']?.toString() ?? '';
    _vehicleController.text = document['vehicleNo']?.toString() ?? '';
    _remarksController.text = document['remarks']?.toString() ?? '';
    _savedFormSnapshot = _formPayload();
    _persistDocumentCache(document);
  }

  Future<void> _save() async {
    if (_document == null) return;

    setState(() => _busy = true);
    try {
      final updated = await saveGatePassDetails(
        context,
        widget.api,
        widget.outslip,
        payload: _formPayload(),
        currentDocument: _document!,
        offline: widget.offline,
      );
      if (updated != null && mounted) {
        setState(() => _applyDocument(updated));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markExited() async {
    if (_document == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark gate pass exited?'),
        content: const Text(
          'This records the vehicle as having left the premises. '
          'You cannot undo this from mobile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark exited'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = await markGatePassAsExited(
        context,
        widget.api,
        widget.outslip,
        payload: _formPayload(),
        currentDocument: _document!,
        offline: widget.offline,
      );
      if (updated != null && mounted) {
        setState(() => _applyDocument(updated));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    if (_document == null) return;

    setState(() => _busy = true);
    try {
      await printGatePassDocument(
        context,
        widget.api,
        widget.outslip,
        document: _mergedDocument(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _summaryTile(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactField(String label, TextEditingController controller, {bool readOnly = false}) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      decoration: _fieldDecoration.copyWith(labelText: label),
    );
  }

  Widget _buildDetailsTab(Map<String, dynamic> document) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final readOnly = !_canEdit;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.maroon,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 12, 16, _bottomBarHeight + bottomInset + 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.offline)
            FieldOfflineBanner(
              label: _offlineBannerLabel,
              hint: OfflineCache.offlineReconnectHint,
            ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          document['customerName']?.toString() ?? 'Customer',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                        ),
                      ),
                      FieldStatusChip(
                        document['outslipStatus']?.toString() ?? widget.outslip['status']?.toString(),
                      ),
                      if (isGatePassExited(document)) ...[
                        const SizedBox(width: 8),
                        FieldStatusChip(document['status']?.toString()),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryTile('Gate Pass', document['gatePassNo']?.toString() ?? '—'),
                      _summaryTile('Outslip', document['outslipNo']?.toString() ?? '—'),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryTile('PO No.', document['purchaseOrderNo']?.toString() ?? '—'),
                      _summaryTile('Date', document['displayDate']?.toString() ?? '—'),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryTile('Time Out', document['displayTimeOut']?.toString() ?? '—'),
                      _summaryTile(
                        'Items',
                        '${(document['items'] as List?)?.length ?? 0}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _compactField('Destination', _destinationController, readOnly: readOnly),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _compactField('Driver', _driverController, readOnly: readOnly)),
              const SizedBox(width: 10),
              Expanded(child: _compactField('Plate No.', _plateController, readOnly: readOnly)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _compactField('Vehicle', _vehicleController, readOnly: readOnly)),
              const SizedBox(width: 10),
              Expanded(child: _compactField('Remarks', _remarksController, readOnly: readOnly)),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildItemsTab(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.maroon,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No items on this gate pass.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.maroon,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _bottomBarHeight + 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final code = item['productCode']?.toString() ?? '';
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppTheme.maroon.withValues(alpha: 0.12),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppTheme.maroon,
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
                      if (code.isNotEmpty)
                        Text(code, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        'Qty ${item['quantity'] ?? '—'} ${item['unit'] ?? 'UNIT'}'
                        '${(item['brand']?.toString() ?? '').isNotEmpty ? ' · ${item['brand']}' : ''}',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
    );
  }

  Widget? _buildBottomBar(Map<String, dynamic> document) {
    final canPrint = _document != null;
    final canSave = _canEdit;
    final canExit = _canMarkExited;
    final printTooltip = widget.offline && _document == null
        ? GatePassPage.offlineLoadMessage
        : printRequiresConnectionMessage;

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
            SizedBox(
              width: double.infinity,
              child: canPrint
                  ? FilledButton.icon(
                      onPressed: _busy ? null : _print,
                      icon: const Icon(Icons.print_outlined),
                      label: Text(_busy ? 'Working…' : 'Print gate pass'),
                    )
                  : Tooltip(
                      message: printTooltip,
                      child: FilledButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print gate pass'),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || !canSave ? null : _save,
                    child: const Text('Save'),
                  ),
                ),
                if (canExit) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _markExited,
                      child: const Text('Mark exited'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedScaffold(Map<String, dynamic> document, List<Map<String, dynamic>> items) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !_hasUnsavedChanges) return;
        if (await _confirmDiscardChanges() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: transactionAppBar(
            context,
            title: document['gatePassNo']?.toString() ?? 'Gate pass',
            showBack: true,
            onBack: () {
              _onWillPop().then((allow) {
                if (allow && context.mounted) Navigator.of(context).pop();
              });
            },
            extraActions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading || _busy ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Print gate pass',
                onPressed: _busy || _document == null ? null : _print,
                icon: const Icon(Icons.print_outlined),
              ),
            ],
            bottom: TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                const Tab(text: 'Details'),
                Tab(text: 'Items (${items.length})'),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomBar(document),
          body: TabBarView(
            children: [
              _buildDetailsTab(document),
              _buildItemsTab(items),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScaffold() {
    return Scaffold(
      appBar: transactionAppBar(context, title: 'Gate pass', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.offline) ...[
            FieldOfflineBanner(label: _offlineBannerLabel),
            Card(
              child: const ListTile(
                leading: Icon(Icons.info_outline_rounded, color: AppTheme.maroon),
                title: Text(
                  GatePassPage.offlineLoadMessage,
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
          ] else ...[
            FieldErrorBanner(
              message: _loadError ?? 'Gate pass unavailable.',
              onRetry: _load,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_loading ? 'Loading…' : 'Try again'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final items = (document?['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (_loading && document == null && _loadError == null) {
      return Scaffold(
        appBar: transactionAppBar(context, title: 'Gate pass', showBack: true),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.maroon)),
      );
    }

    if (document == null) {
      return _buildErrorScaffold();
    }

    return _buildLoadedScaffold(document, items);
  }
}
