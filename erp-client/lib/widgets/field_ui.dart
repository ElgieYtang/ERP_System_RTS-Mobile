import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../navigation/app_navigation.dart';
import '../services/transaction_actions.dart';
import '../theme/app_theme.dart';

String fieldRowId(Map<String, dynamic> row) =>
    row['dbId']?.toString() ?? row['id']?.toString() ?? '';

/// Matches Laravel `SetupStatus::toFrontend` (`Active` / `Inactive`).
bool fieldSetupRowIsActive(Map<String, dynamic> row) {
  final status = row['status']?.toString().toLowerCase() ?? '';
  return status != 'inactive';
}

/// Setup item label for dropdowns (Laravel presenter or legacy raw `setup_items` rows).
String fieldSetupItemDisplayName(Map<String, dynamic> product) {
  final name = product['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final legacy = product['item_name']?.toString().trim();
  if (legacy != null && legacy.isNotEmpty) return legacy;
  return 'Item';
}

String fieldSetupItemCode(Map<String, dynamic> product) {
  final code = product['code']?.toString().trim();
  if (code != null && code.isNotEmpty) return code;
  final id = product['id']?.toString().trim();
  if (id != null && id.isNotEmpty) {
    return 'ITM-${id.padLeft(4, '0')}';
  }
  return '';
}

String fieldSetupItemLabel(Map<String, dynamic> product) {
  final code = fieldSetupItemCode(product);
  final name = fieldSetupItemDisplayName(product);
  if (code.isEmpty) return name;
  return '$code — $name';
}

String fieldDbId(Map<String, dynamic> row) =>
    row['dbId']?.toString() ?? row['id']?.toString() ?? '';

String fieldFormatMoney(dynamic value) {
  final amount = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  final formatted = NumberFormat('#,##0.00', 'en_US').format(amount);
  return '₱$formatted';
}

/// Billing records from the API use [amount]; older cached rows may use [total].
num fieldBillingTotal(Map<String, dynamic> billing) {
  final raw = billing['amount'] ?? billing['total'];
  final value = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
  return fieldRoundMoney(value);
}

num fieldBillingPaid(Map<String, dynamic> billing) {
  final raw = billing['paidAmount'];
  final value = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;
  return fieldRoundMoney(value);
}

num fieldBillingBalanceDue(Map<String, dynamic> billing) {
  final fromApi = billing['balanceDue'];
  if (fromApi != null) {
    final value = fromApi is num ? fromApi.toDouble() : double.tryParse(fromApi.toString());
    if (value != null) return fieldRoundMoney(value);
  }
  return fieldRoundMoney(fieldBillingTotal(billing) - fieldBillingPaid(billing));
}

/// Match API currency rounding (2 decimal places).
double fieldRoundMoney(num value) {
  return (value.toDouble() * 100).round() / 100;
}

String fieldStatusLabel(String? status) {
  final raw = (status ?? '').trim();
  if (raw.isEmpty) return '—';
  return raw
      .split('_')
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// Matches web `frontend/src/lib/status.js` badge variants.
String fieldStatusVariant(String? status) {
  switch ((status ?? '').trim().toLowerCase()) {
    case 'draft':
      return 'draft';
    case 'pending':
    case 'partial':
    case 'out_for_delivery':
    case 'unpaid':
    case 'partially_paid':
    case 'low stock':
      return 'pending';
    case 'approved':
    case 'completed':
    case 'fully_received':
    case 'released':
    case 'delivered':
    case 'paid':
    case 'in stock':
      return 'approved';
    case 'rejected':
    case 'cancelled':
    case 'inactive':
    case 'out of stock':
      return 'rejected';
    case 'for_dispatch':
    case 'active':
      return 'current';
    case 'exited':
      return 'approved';
    default:
      return 'draft';
  }
}

class FieldStatusStyle {
  const FieldStatusStyle({required this.foreground, required this.background});

  final Color foreground;
  final Color background;
}

FieldStatusStyle fieldStatusStyle(String? status) {
  switch (fieldStatusVariant(status)) {
    case 'approved':
      return const FieldStatusStyle(
        foreground: AppTheme.successText,
        background: Color(0xFFDCFCE7),
      );
    case 'pending':
      return const FieldStatusStyle(
        foreground: AppTheme.warningText,
        background: Color(0xFFFEF3C7),
      );
    case 'rejected':
      return const FieldStatusStyle(
        foreground: AppTheme.errorText,
        background: AppTheme.errorBg,
      );
    case 'current':
      return const FieldStatusStyle(
        foreground: AppTheme.maroon,
        background: AppTheme.maroonLight,
      );
    case 'draft':
    default:
      return const FieldStatusStyle(
        foreground: AppTheme.textSecondary,
        background: Color(0xFFF3F4F6),
      );
  }
}

class FieldStatusChip extends StatelessWidget {
  const FieldStatusChip(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final style = fieldStatusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        fieldStatusLabel(status),
        style: TextStyle(
          color: style.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class FieldErrorBanner extends StatelessWidget {
  const FieldErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.errorBg,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.error_outline_rounded, color: AppTheme.errorText),
        title: Text(message, style: const TextStyle(color: AppTheme.errorText, fontSize: 13)),
        trailing: IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.errorText),
          tooltip: 'Retry',
        ),
      ),
    );
  }
}

void fieldShowBackOnlineSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Back online — data updated.')),
  );
}

/// Shown when cross-module workflow rules cannot be trusted (partial offline cache).
const partialCacheWorkflowMessage =
    'Some linked records are missing from cache — create and convert actions stay hidden until you reconnect.';

/// Shown when dashboard counts come from stale summary stats instead of list rows.
const approximateHomeCountsMessage =
    'Dashboard counts are approximate — reconnect to refresh module lists.';

/// Shown when recomputed list counts disagree with cached summary stats.
const homeCountsMismatchMessage =
    'Dashboard counts may be incomplete — some cached lists are missing.';

class FieldPartialCacheBanner extends StatelessWidget {
  const FieldPartialCacheBanner({
    super.key,
    this.message = partialCacheWorkflowMessage,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.maroonLight,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        dense: true,
        minVerticalPadding: 12,
        leading: const Icon(Icons.link_off_rounded, color: AppTheme.maroon),
        title: Text(
          message,
          style: const TextStyle(color: AppTheme.maroon, fontSize: 13, height: 1.35),
        ),
      ),
    );
  }
}

class FieldOfflineBanner extends StatelessWidget {
  const FieldOfflineBanner({
    super.key,
    required this.label,
    this.hint,
  });

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFEF3C7),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        dense: true,
        minVerticalPadding: 12,
        leading: const Icon(Icons.cloud_off_outlined, color: AppTheme.warningText),
        title: Text(
          label,
          style: const TextStyle(color: AppTheme.warningText, fontSize: 13),
        ),
        subtitle: hint == null
            ? null
            : Text(
                hint!,
                style: const TextStyle(color: AppTheme.warningText, fontSize: 12, height: 1.35),
              ),
      ),
    );
  }
}

void fieldShowOfflineBlocked(BuildContext context) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Offline — reconnect to update records.')),
  );
}

class FieldFilterBar extends StatelessWidget {
  const FieldFilterBar({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<({String id, String label})> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: options.map((option) {
          final selected = option.id == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(option.label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onChanged(option.id),
              selectedColor: AppTheme.maroonLight,
              backgroundColor: Colors.white,
              side: BorderSide(color: selected ? AppTheme.maroon : AppTheme.border),
              labelStyle: TextStyle(
                color: selected ? AppTheme.maroon : AppTheme.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FieldEmptyState extends StatelessWidget {
  const FieldEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppTheme.maroonLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppTheme.maroon),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class FieldQuietState extends StatelessWidget {
  const FieldQuietState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: AppTheme.maroonLight,
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.check_circle_outline_rounded, color: AppTheme.maroon),
        title: Text('No open jobs', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class FieldDialogForm extends StatelessWidget {
  const FieldDialogForm({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class FieldSectionTitle extends StatelessWidget {
  const FieldSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
      ),
    );
  }
}

class FieldLineItems extends StatelessWidget {
  const FieldLineItems({
    super.key,
    required this.items,
    this.showSerialProgress = false,
  });

  final List<Map<String, dynamic>> items;
  final bool showSerialProgress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No line items.', style: TextStyle(color: AppTheme.textSecondary));
    }

    return Column(
      children: items.map((item) {
        final name = item['productName']?.toString() ?? 'Item';
        final qty = item['quantity'] ?? item['received'] ?? '—';
        final progress = showSerialProgress ? deliveryLineSerialProgress(item) : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    if (progress != null && progress.needed > 0)
                      Text(
                        'Serials ${progress.captured}/${progress.needed}',
                        style: TextStyle(
                          fontSize: 12,
                          color: progress.complete ? AppTheme.successText : AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Text('Qty $qty', style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.maroon)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class FieldDetailMeta extends StatelessWidget {
  const FieldDetailMeta({super.key, required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 14, height: 1.45, color: AppTheme.textSecondary),
              children: [
                TextSpan(
                  text: '${rows[i].label}: ',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                TextSpan(text: rows[i].value),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Groups outline/print actions in a row; workflow buttons stack full-width below.
class FieldDetailActions extends StatelessWidget {
  const FieldDetailActions({
    super.key,
    this.secondary = const [],
    this.primary = const [],
  });

  final List<Widget> secondary;
  final List<Widget> primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (secondary.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: secondary,
          ),
          if (primary.isNotEmpty) const SizedBox(height: 12),
        ],
        for (var i = 0; i < primary.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          primary[i],
        ],
      ],
    );
  }
}

class FieldDetailScaffold extends StatelessWidget {
  const FieldDetailScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.children,
    this.secondaryActions,
    this.primaryActions,
    this.actions,
    this.workflowNotice,
    this.workflowNoticeLoading = false,
  });

  final String title;
  final String subtitle;
  final String? status;
  final List<Widget> children;
  final List<Widget>? secondaryActions;
  final List<Widget>? primaryActions;
  final List<Widget>? actions;
  final String? workflowNotice;
  final bool workflowNoticeLoading;

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryActions ?? const [];
    final primary = primaryActions ?? actions ?? const [];
    final hasActions = secondary.isNotEmpty || primary.isNotEmpty;

    return Scaffold(
      appBar: transactionAppBar(context, title: title, showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                          subtitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(width: 8),
                        FieldStatusChip(status),
                      ],
                    ],
                  ),
                  if (children.isNotEmpty) const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
          if (workflowNotice != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.maroonLight,
              child: ListTile(
                dense: true,
                leading: workflowNoticeLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.maroon),
                      )
                    : const Icon(Icons.info_outline_rounded, color: AppTheme.maroon),
                title: Text(
                  workflowNotice!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.35),
                ),
              ),
            ),
          ],
          if (hasActions) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FieldDetailActions(
                  secondary: secondary,
                  primary: primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
