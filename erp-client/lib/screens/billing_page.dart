import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/api_errors.dart';
import '../services/offline_cache.dart';
import '../navigation/mobile_modules.dart';
import '../navigation/transaction_detail_host.dart';
import '../services/transaction_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';
import '../widgets/print_document_button.dart';
import '../widgets/transaction_workflows.dart';

class _ArRecurringItem {
  const _ArRecurringItem({required this.accountLabel, required this.monthlyFee});

  final String accountLabel;
  final double monthlyFee;
}

InputDecoration _billingFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  bool _loading = true;
  bool _fromCache = false;
  bool _saving = false;
  bool _showBillingEntries = false;
  bool _showDeductions = true;
  bool _showContractSection = false;
  bool _showRecurringItems = false;
  String? _error;
  String? _offlineLabel;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _projects = [];

  String? _customerId;
  String? _projectId;
  String? _billingId;
  DateTime _transactionDate = DateTime.now();

  final _invoiceController = TextEditingController();
  final _withholdingController = TextEditingController(text: '0.00');
  final _retentionController = TextEditingController(text: '0.00');
  final _recoupmentController = TextEditingController(text: '0.00');
  final _mobilizationController = TextEditingController(text: '0.00');
  final _netController = TextEditingController();
  final _remarksController = TextEditingController();
  final _contractAmountController = TextEditingController(text: '0.00');
  final _contractMonthlyController = TextEditingController(text: '0.00');
  final _accountLocationController = TextEditingController();
  final _lineMonthlyFeeController = TextEditingController();
  final _recurringDayController = TextEditingController();

  DateTime? _contractStart;
  DateTime? _contractEnd;
  DateTime? _entriesDateFrom;
  DateTime? _entriesDateTo;
  final List<_ArRecurringItem> _recurringItems = [];

  @override
  void initState() {
    super.initState();
    for (final c in [
      _withholdingController,
      _retentionController,
      _recoupmentController,
      _mobilizationController,
    ]) {
      c.addListener(_syncNetAmount);
    }
    _recurringDayController.text = '${DateTime.now().day}';
    _load();
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _withholdingController.dispose();
    _retentionController.dispose();
    _recoupmentController.dispose();
    _mobilizationController.dispose();
    _netController.dispose();
    _remarksController.dispose();
    _contractAmountController.dispose();
    _contractMonthlyController.dispose();
    _accountLocationController.dispose();
    _lineMonthlyFeeController.dispose();
    _recurringDayController.dispose();
    super.dispose();
  }

  double _parseMoney(TextEditingController controller) {
    final raw = controller.text.trim().replaceAll(',', '');
    return double.tryParse(raw) ?? 0;
  }

  Map<String, dynamic>? get _selectedBilling {
    if (_billingId == null) return null;
    for (final row in _openBillingsForCustomer) {
      if (fieldRowId(row) == _billingId) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> get _openBillingsForCustomer {
    Iterable<Map<String, dynamic>> list = _rows.where((r) => r['paymentStatus'] != 'paid');
    if (_customerId != null && _customerId!.isNotEmpty) {
      list = list.where((r) => r['customerId']?.toString() == _customerId);
    }
    return list.toList();
  }

  List<Map<String, dynamic>> get _listRows {
    Iterable<Map<String, dynamic>> list = _rows;
    if (_customerId != null && _customerId!.isNotEmpty) {
      list = list.where((r) => r['customerId']?.toString() == _customerId);
    }
    if (_entriesDateFrom != null || _entriesDateTo != null) {
      list = list.where((row) {
        final date = _parseBillingRowDate(row);
        if (date == null) return true;
        if (_entriesDateFrom != null && date.isBefore(_entriesDateFrom!)) return false;
        if (_entriesDateTo != null) {
          final end = DateTime(_entriesDateTo!.year, _entriesDateTo!.month, _entriesDateTo!.day, 23, 59, 59);
          if (date.isAfter(end)) return false;
        }
        return true;
      });
    }
    return list.toList();
  }

  DateTime? _parseBillingRowDate(Map<String, dynamic> row) {
    final raw = row['billingDate']?.toString() ?? row['displayDate']?.toString();
    if (raw == null || raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    try {
      final parts = raw.split(',').first.trim();
      return DateTime.tryParse(parts);
    } catch (_) {
      return null;
    }
  }

  double get _recurringItemsTotal =>
      _recurringItems.fold(0.0, (sum, item) => sum + item.monthlyFee);

  void _addRecurringLine() {
    final label = _accountLocationController.text.trim();
    final fee = _parseMoney(_lineMonthlyFeeController);
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter account name — location.')),
      );
      return;
    }
    if (fee <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a monthly recurring fee greater than zero.')),
      );
      return;
    }
    setState(() {
      _recurringItems.add(_ArRecurringItem(accountLabel: label, monthlyFee: fee));
      _accountLocationController.clear();
      _lineMonthlyFeeController.clear();
    });
  }

  Future<void> _pickContractDate({required bool isStart}) async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }
    final initial = isStart ? _contractStart : _contractEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _contractStart = picked;
        if (_contractEnd != null && _contractEnd!.isBefore(picked)) {
          _contractEnd = picked;
        }
      } else {
        _contractEnd = picked;
        if (_contractStart != null && _contractStart!.isAfter(picked)) {
          _contractStart = picked;
        }
      }
    });
  }

  Future<void> _pickEntriesDate({required bool isFrom}) async {
    if (_fromCache) return;
    final initial = isFrom ? _entriesDateFrom : _entriesDateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _entriesDateFrom = picked;
      } else {
        _entriesDateTo = picked;
      }
    });
  }

  void _syncNetAmount() {
    final billing = _selectedBilling;
    final gross = billing != null ? fieldBillingBalanceDue(billing).toDouble() : 0;
    final deductions = _parseMoney(_withholdingController) +
        _parseMoney(_retentionController) +
        _parseMoney(_recoupmentController) +
        _parseMoney(_mobilizationController);
    final net = fieldRoundMoney((gross - deductions).clamp(0, double.infinity));
    final text = billing == null ? '' : net.toStringAsFixed(2);
    if (_netController.text != text) {
      _netController.text = text;
    }
  }

  void _onBillingChanged(String? id) {
    setState(() => _billingId = id);
    _syncNetAmount();
  }

  void _onCustomerChanged(String? id) {
    setState(() {
      _customerId = id;
      _billingId = null;
      final open = _openBillingsForCustomer;
      if (open.isNotEmpty) {
        _billingId = fieldRowId(open.first);
      }
    });
    _syncNetAmount();
  }

  String _formatApiDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(dynamic billing) {
    return billing['displayDate']?.toString() ??
        billing['billingDate']?.toString() ??
        '—';
  }

  String _formatDrReference(dynamic referenceDrId) {
    final raw = referenceDrId?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final upper = raw.toUpperCase();
    if (upper.startsWith('DR-') || upper.startsWith('DR ')) return raw;
    return 'DR-$raw';
  }

  String _billingStatementMenuLabel(Map<String, dynamic> billing) {
    final due = fieldFormatMoney(fieldBillingBalanceDue(billing));
    final dr = _formatDrReference(billing['referenceDrId']);
    return '${billing['id']} · $dr · $due due';
  }

  String? _composeRemarks() {
    final parts = <String>[];
    if (_projectId != null) {
      String? name;
      for (final p in _projects) {
        if (p['id']?.toString() == _projectId) {
          name = p['name']?.toString();
          break;
        }
      }
      if (name != null && name.isNotEmpty) parts.add('Project: $name');
    }
    final wht = _parseMoney(_withholdingController);
    final ret = _parseMoney(_retentionController);
    final rec = _parseMoney(_recoupmentController);
    final mob = _parseMoney(_mobilizationController);
    if (wht > 0) parts.add('WHT ${fieldFormatMoney(wht)}');
    if (ret > 0) parts.add('Retention ${fieldFormatMoney(ret)}');
    if (rec > 0) parts.add('Recoupment ${fieldFormatMoney(rec)}');
    if (mob > 0) parts.add('Mobilization ${fieldFormatMoney(mob)}');
    final contractAmt = _parseMoney(_contractAmountController);
    final contractMonthly = _parseMoney(_contractMonthlyController);
    if (contractAmt > 0) parts.add('Contract ${fieldFormatMoney(contractAmt)}');
    if (contractMonthly > 0) parts.add('Mo. recurring ${fieldFormatMoney(contractMonthly)}');
    if (_contractStart != null) parts.add('Start ${_formatApiDate(_contractStart!)}');
    if (_contractEnd != null) parts.add('End ${_formatApiDate(_contractEnd!)}');
    final billDay = int.tryParse(_recurringDayController.text.trim());
    if (billDay != null && billDay >= 1 && billDay <= 31) {
      parts.add('Bill day $billDay');
    }
    for (final item in _recurringItems) {
      parts.add('${item.accountLabel}: ${fieldFormatMoney(item.monthlyFee)}/mo');
    }
    final user = _remarksController.text.trim();
    if (user.isNotEmpty) parts.add(user);
    if (parts.isEmpty) return null;
    final joined = parts.join(' · ');
    return joined.length > 255 ? joined.substring(0, 255) : joined;
  }

  Future<void> _pickTransactionDate() async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _transactionDate = picked);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
      _offlineLabel = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getList('/billings'),
        widget.api.getList('/setup/customers'),
        widget.api.getList('/setup/projects'),
      ]);
      final billings = results[0].cast<Map<String, dynamic>>();
      final customers = results[1].cast<Map<String, dynamic>>();
      final projects = results[2].cast<Map<String, dynamic>>();
      await OfflineCache.saveList(OfflineCache.billings, billings);
      await OfflineCache.saveList(OfflineCache.soaCustomers, customers);
      await OfflineCache.saveList(OfflineCache.projects, projects);
      if (!mounted) return;
      setState(() {
        _rows = billings;
        _customers = customers.where((c) => c['status'] != 'Inactive').toList();
        _projects = projects;
        _customerId ??=
            _customers.isNotEmpty ? _customers.first['id']?.toString() : null;
        final open = _openBillingsForCustomer;
        if (_billingId == null && open.isNotEmpty) {
          _billingId = fieldRowId(open.first);
        }
        _loading = false;
      });
      _syncNetAmount();
    } catch (error) {
      final cachedBillings = await OfflineCache.loadList(OfflineCache.billings);
      final cachedCustomers = await OfflineCache.loadList(OfflineCache.soaCustomers);
      final cachedProjects = await OfflineCache.loadList(OfflineCache.projects);
      if (!mounted) return;
      if (cachedBillings.rows.isNotEmpty) {
        setState(() {
          _rows = cachedBillings.rows;
          _customers = cachedCustomers.rows.where((c) => c['status'] != 'Inactive').toList();
          _projects = cachedProjects.rows;
          _fromCache = true;
          _offlineLabel = OfflineCache.staleLabel(cachedBillings.savedAt);
          _error = friendlyApiError(error);
          _loading = false;
        });
        _syncNetAmount();
      } else {
        setState(() {
          _error = friendlyApiError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveArEntry() async {
    if (_fromCache) {
      fieldShowOfflineBlocked(context);
      return;
    }
    final billing = _selectedBilling;
    if (billing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a billing statement with a balance due.')),
      );
      return;
    }
    if (!canRecordBillingPayment(billing)) {
      showTransactionActionBlocked(context, 'This billing is already paid.');
      return;
    }

    final net = _parseMoney(_netController);
    if (net <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Net amount must be greater than zero.')),
      );
      return;
    }

    final remaining = fieldBillingBalanceDue(billing).toDouble();
    var amount = fieldRoundMoney(net);
    if (amount > remaining) {
      if (amount - remaining <= 0.05) {
        amount = fieldRoundMoney(remaining);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Net amount cannot exceed ${fieldFormatMoney(remaining)}.')),
        );
        return;
      }
    }

    final id = fieldRowId(billing);
    if (id.isEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.api.post('/billings/${Uri.encodeComponent(id)}/payments', {
        'amount': amount,
        'date': _formatApiDate(_transactionDate),
        if (_invoiceController.text.trim().isNotEmpty) 'reference': _invoiceController.text.trim(),
        if (_composeRemarks() != null) 'remarks': _composeRemarks(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing saved — payment recorded.')),
      );
      _withholdingController.text = '0.00';
      _retentionController.text = '0.00';
      _recoupmentController.text = '0.00';
      _mobilizationController.text = '0.00';
      _invoiceController.clear();
      _remarksController.clear();
      _contractAmountController.text = '0.00';
      _contractMonthlyController.text = '0.00';
      _recurringItems.clear();
      _contractStart = null;
      _contractEnd = null;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moneyField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: readOnly
            ? null
            : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
        decoration: _billingFieldDecoration(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final listRows = _listRows;
    const headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.textSecondary,
    );

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.maroon,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_fromCache && _offlineLabel != null)
            FieldOfflineBanner(
              label: _offlineLabel!,
              hint: OfflineCache.offlineReconnectHint,
            ),
          if (_error != null && !_fromCache) FieldErrorBanner(message: _error!, onRetry: _load),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Create AR Entry',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Like office Receivables: client, project, invoice, deductions, contract notes. '
                    'Payment is saved against a billing statement (from delivery).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('billing_client_$_customerId'),
                    isExpanded: true,
                    initialValue: _customerId?.isNotEmpty == true ? _customerId : null,
                    decoration: _billingFieldDecoration('Client'),
                    items: _customers
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id']?.toString(),
                            child: Text(
                              c['name']?.toString() ?? 'Customer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    selectedItemBuilder: (context) => _customers
                        .map(
                          (c) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              c['name']?.toString() ?? 'Customer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _fromCache ? null : _onCustomerChanged,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('billing_project_$_projectId'),
                    isExpanded: true,
                    initialValue: _projectId?.isNotEmpty == true ? _projectId : null,
                    decoration: _billingFieldDecoration('Project'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Optional —')),
                      ..._projects.map(
                        (p) => DropdownMenuItem(
                          value: p['id']?.toString(),
                          child: Text(
                            p['name']?.toString() ?? 'Project',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _fromCache ? null : (v) => setState(() => _projectId = v),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _fromCache ? null : _pickTransactionDate,
                    child: InputDecorator(
                      decoration: _billingFieldDecoration('Transaction date'),
                      child: Text(_formatApiDate(_transactionDate)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _invoiceController,
                    readOnly: _fromCache,
                    decoration: _billingFieldDecoration('Invoice no. / reference'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('billing_bs_${_customerId}_$_billingId'),
                    isExpanded: true,
                    initialValue: _billingId?.isNotEmpty == true ? _billingId : null,
                    decoration: _billingFieldDecoration('Billing statement'),
                    items: _openBillingsForCustomer
                        .map(
                          (b) => DropdownMenuItem(
                            value: fieldRowId(b),
                            child: Text(
                              _billingStatementMenuLabel(b),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    selectedItemBuilder: (context) => _openBillingsForCustomer
                        .map(
                          (b) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              b['id']?.toString() ?? 'Billing',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _fromCache ? null : _onBillingChanged,
                  ),
                  if (_openBillingsForCustomer.isEmpty) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'No open billing for this client. Create billing from a delivered delivery receipt first, '
                      'or pick a client that still has a balance due.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
                    ),
                  ],
                  if (_selectedBilling != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Statement total ${fieldFormatMoney(fieldBillingTotal(_selectedBilling!))} · '
                      'Balance ${fieldFormatMoney(fieldBillingBalanceDue(_selectedBilling!))}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => setState(() => _showDeductions = !_showDeductions),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Deductions & net',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          Icon(
                            _showDeductions ? Icons.expand_less : Icons.expand_more,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showDeductions) ...[
                    _moneyField('Withholding tax amount', _withholdingController),
                    _moneyField('Retention amount', _retentionController),
                    _moneyField('Recoupment amount', _recoupmentController),
                    _moneyField('Mobilization amount', _mobilizationController),
                    _moneyField('Net amount', _netController, readOnly: true),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      controller: _remarksController,
                      readOnly: _fromCache,
                      maxLines: 3,
                      decoration: _billingFieldDecoration('Remarks'),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showContractSection = !_showContractSection),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Contract (reference)',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          Icon(
                            _showContractSection ? Icons.expand_less : Icons.expand_more,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showContractSection) ...[
                    _moneyField('Contract amount', _contractAmountController),
                    _moneyField('Monthly recurring', _contractMonthlyController),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _fromCache ? null : () => _pickContractDate(isStart: true),
                            child: InputDecorator(
                              decoration: _billingFieldDecoration('Start date'),
                              child: Text(_contractStart == null ? '—' : _formatApiDate(_contractStart!)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _fromCache ? null : () => _pickContractDate(isStart: false),
                            child: InputDecorator(
                              decoration: _billingFieldDecoration('End date'),
                              child: Text(_contractEnd == null ? '—' : _formatApiDate(_contractEnd!)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Text('Every', style: TextStyle(fontSize: 13)),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 56,
                          child: TextFormField(
                            controller: _recurringDayController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: _billingFieldDecoration('Day'),
                          ),
                        ),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 14, left: 8),
                            child: Text('of the month', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _saving || _fromCache || _openBillingsForCustomer.isEmpty
                          ? null
                          : _saveArEntry,
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _showRecurringItems,
                onExpansionChanged: (v) => setState(() => _showRecurringItems = v),
                title: const Text('Recurring items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                subtitle: Text(
                  _recurringItems.isEmpty
                      ? 'Account / location lines (saved in remarks)'
                      : '${_recurringItems.length} item(s) · ${fieldFormatMoney(_recurringItemsTotal)}/mo total',
                  style: const TextStyle(fontSize: 12),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _accountLocationController,
                          readOnly: _fromCache,
                          decoration: _billingFieldDecoration('Account name — location'),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _lineMonthlyFeeController,
                          readOnly: _fromCache,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _billingFieldDecoration('Monthly recurring fee'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _fromCache ? null : _addRecurringLine,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add to list'),
                        ),
                        if (_recurringItems.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const FieldSectionTitle('Items'),
                          ..._recurringItems.asMap().entries.map((entry) {
                            final i = entry.key;
                            final item = entry.value;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                title: Text(item.accountLabel, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(fieldFormatMoney(item.monthlyFee)),
                                trailing: _fromCache
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        onPressed: () => setState(() => _recurringItems.removeAt(i)),
                                      ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _showBillingEntries = !_showBillingEntries),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined, color: AppTheme.maroon, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Billing entries',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              Text(
                                listRows.isEmpty
                                    ? 'No records for this client'
                                    : '${listRows.length} record${listRows.length == 1 ? '' : 's'}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _showBillingEntries ? Icons.expand_less : Icons.expand_more,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: !_showBillingEntries
                      ? const SizedBox.shrink()
                      : Column(
                    children: [
                      const Divider(height: 1),
                      if (listRows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: FieldEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No billing records',
                            subtitle: 'Change client or pull to refresh.',
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _fromCache ? null : () => _pickEntriesDate(isFrom: true),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Date from',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    child: Text(
                                      _entriesDateFrom == null ? 'Any' : _formatApiDate(_entriesDateFrom!),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _fromCache ? null : () => _pickEntriesDate(isFrom: false),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Date to',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    child: Text(
                                      _entriesDateTo == null ? 'Any' : _formatApiDate(_entriesDateTo!),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text('Date', style: headerStyle)),
                              Expanded(flex: 3, child: Text('Client', style: headerStyle)),
                              Expanded(flex: 2, child: Text('DR', style: headerStyle)),
                              Expanded(
                                flex: 2,
                                child: Text('Amount', style: headerStyle, textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ...listRows.map((row) {
                          final status = row['paymentStatus']?.toString() ?? 'unpaid';

                          return Column(
                            children: [
                              InkWell(
                                onTap: () => pushTransactionDetail(
                                  context,
                                  widget.api,
                                  MobileModule.billing,
                                  row,
                                  offline: _fromCache,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _formatDisplayDate(row),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          row['customerName']?.toString() ?? '—',
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          row['referenceDrId']?.toString() ?? '—',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              fieldFormatMoney(fieldBillingTotal(row)),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            FieldStatusChip(status),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class BillingDetailPage extends StatelessWidget {
  const BillingDetailPage({
    super.key,
    required this.billing,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
  });

  final Map<String, dynamic> billing;
  final String? workflowNotice;
  final bool workflowNoticeLoading;

  @override
  Widget build(BuildContext context) {
    final payments = (billing['payments'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final total = fieldBillingTotal(billing);
    final paid = fieldBillingPaid(billing);
    final balanceDue = fieldBillingBalanceDue(billing);

    return FieldDetailScaffold(
      title: billing['id']?.toString() ?? 'Billing',
      subtitle: billing['customerName']?.toString() ?? 'Customer —',
      status: billing['paymentStatus']?.toString(),
      workflowNotice: workflowNotice,
      workflowNoticeLoading: workflowNoticeLoading,
      secondaryActions: [
        PrintDocumentButton(
          onPrint: () => printBilling(billing),
          label: 'Print PDF',
        ),
      ],
      children: [
        Text(
          balanceDue > 0 ? 'Amount due' : 'Balance',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fieldFormatMoney(balanceDue > 0 ? balanceDue : 0),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppTheme.maroon,
            height: 1.15,
          ),
        ),
        if (paid > 0 || total > 0) ...[
          const SizedBox(height: 6),
          Text(
            'Total ${fieldFormatMoney(total)} · Paid ${fieldFormatMoney(paid)}',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.35),
          ),
        ],
        if (balanceDue > 0) ...[
          const SizedBox(height: 12),
          const Text(
            'To collect the remaining balance, go back to Billing and use Create billing. '
            'Select this billing statement, enter deductions if any, then Save.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        FieldDetailMeta(
          rows: [
            (
              label: 'Billing date',
              value: '${billing['displayDate'] ?? billing['billingDate'] ?? '—'}',
            ),
            (label: 'Delivery receipt', value: '${billing['referenceDrId'] ?? '—'}'),
            (label: 'Total', value: fieldFormatMoney(total)),
            (label: 'Paid', value: fieldFormatMoney(paid)),
          ],
        ),
        if (payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          const FieldSectionTitle('Payments'),
          ...payments.map(
            (payment) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${payment['id'] ?? 'Payment'} · ${fieldFormatMoney(payment['amount'])} · '
                '${payment['displayDate'] ?? payment['date'] ?? '—'}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
