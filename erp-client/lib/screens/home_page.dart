import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/mobile_modules.dart';
import '../services/api_client.dart';
import '../services/dashboard_refresh.dart';
import '../services/home_counts.dart';
import '../services/offline_cache.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';
import '../widgets/field_ui.dart';
import '../widgets/server_connection_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenModule});

  final ValueChanged<MobileModule> onOpenModule;

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _loading = true;
  bool _syncing = false;
  bool _fromCache = false;
  String? _error;
  String? _offlineLabel;
  final Map<MobileModule, int> _counts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showCachedCountsPreview();
    refreshCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshCounts();
    }
  }

  /// Show last counts while refreshing — do not mark offline until API fails.
  Future<void> _showCachedCountsPreview() async {
    final cached = await OfflineCache.loadMap(OfflineCache.homeStats);
    if (!mounted || cached.data == null) return;
    setState(() {
      _counts
        ..clear()
        ..addAll(homeModuleCountsFromStats(cached.data!));
      _loading = false;
    });
  }

  Future<void> refreshCounts() => _load();

  static const _queueModules = {
    MobileModule.quotations,
    MobileModule.purchaseOrders,
    MobileModule.receiving,
    MobileModule.outslips,
    MobileModule.deliveries,
    MobileModule.billing,
    MobileModule.accomplishments,
  };

  int get _totalOpen {
    var sum = 0;
    for (final module in _queueModules) {
      sum += _counts[module] ?? 0;
    }
    return sum;
  }

  List<MobileModuleInfo> get _attentionModules {
    return mobileModules
        .where((module) => _queueModules.contains(module.id) && (_counts[module.id] ?? 0) > 0)
        .toList();
  }

  String _firstName(String? fullName) {
    final trimmed = fullName?.trim() ?? '';
    if (trimmed.isEmpty) return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Future<void> _load() async {
    final wasOffline = _fromCache;
    final blockUi = _counts.isEmpty;
    setState(() {
      _loading = blockUi;
      _syncing = !blockUi;
      _error = null;
      _fromCache = false;
      _offlineLabel = null;
    });

    final api = context.read<ApiClient>();

    try {
      final counts = await DashboardRefresh.fetchModuleCounts(api);

      await OfflineCache.saveMap(
        OfflineCache.homeStats,
        homeStatsPayloadFromCounts(counts),
      );

      if (!mounted) return;
      setState(() {
        _counts
          ..clear()
          ..addAll(counts);
        _loading = false;
        _syncing = false;
        _fromCache = false;
        _offlineLabel = null;
        _error = null;
      });
      if (wasOffline && mounted) fieldShowBackOnlineSnackBar(context);

      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) _prefetchListCaches(api);
      });
    } catch (error) {
      final message = await DashboardRefresh.describeFailure(api, error);
      final cached = await OfflineCache.loadMap(OfflineCache.homeStats);
      if (!mounted) return;

      if (cached.data != null) {
        setState(() {
          _counts
            ..clear()
            ..addAll(homeModuleCountsFromStats(cached.data!));
          _fromCache = true;
          _offlineLabel = OfflineCache.staleLabel(cached.savedAt);
          _error = message;
          _loading = false;
          _syncing = false;
        });
      } else {
        setState(() {
          _error = message;
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  Future<void> _openServerSettings() async {
    await showServerConnectionSheet(context);
    if (mounted) await refreshCounts();
  }

  Future<void> _prefetchListCaches(ApiClient api) async {
    const sources = <(String path, String cacheKey)>[
      ('/quotations', OfflineCache.quotations),
      ('/purchase-orders', OfflineCache.purchaseOrders),
      ('/receivings', OfflineCache.receivings),
      ('/outslips', OfflineCache.outslips),
      ('/delivery-receipts', OfflineCache.deliveries),
      ('/billings', OfflineCache.billings),
      ('/accomplishments', OfflineCache.accomplishments),
    ];

    for (final source in sources) {
      try {
        final rows = await api.getList(source.$1, query: const {'all': '1'});
        await OfflineCache.saveList(source.$2, rows);
      } catch (_) {
        // Offline cache is best-effort; dashboard already has live counts.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _counts.isEmpty && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final auth = context.watch<AuthState>();
    final firstName = _firstName(auth.user?['name']?.toString());
    final attention = _attentionModules;
    final totalOpen = _totalOpen;

    return RefreshIndicator(
      onRefresh: refreshCounts,
      color: AppTheme.maroon,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _DashboardHeroStrip(
            firstName: firstName,
            totalOpen: totalOpen,
            syncing: _syncing,
            offlineLabel: _fromCache ? _offlineLabel : null,
            offlineHint: _fromCache ? OfflineCache.offlineReconnectHint : null,
            error: _error,
            onRetry: refreshCounts,
            onOpenServer: _openServerSettings,
          ),
          if (attention.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _SectionLabel('NEEDS ATTENTION'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 108,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                clipBehavior: Clip.none,
                scrollDirection: Axis.horizontal,
                itemCount: attention.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final module = attention[index];
                  return _AttentionChip(
                    module: module,
                    count: _counts[module.id] ?? 0,
                    onTap: () => widget.onOpenModule(module.id),
                  );
                },
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(16, attention.isNotEmpty ? 24 : 20, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('TRANSACTIONS'),
                const SizedBox(height: 14),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 16),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 4,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: mobileModules.length,
                      itemBuilder: (context, index) {
                        final module = mobileModules[index];
                        return _ModuleIconTile(
                          module: module,
                          count: _counts[module.id] ?? 0,
                          onTap: () => widget.onOpenModule(module.id),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _DashboardHeroStrip extends StatelessWidget {
  const _DashboardHeroStrip({
    required this.firstName,
    required this.totalOpen,
    this.syncing = false,
    this.offlineLabel,
    this.offlineHint,
    this.error,
    this.onRetry,
    this.onOpenServer,
  });

  final String firstName;
  final int totalOpen;
  final bool syncing;
  final String? offlineLabel;
  final String? offlineHint;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenServer;

  @override
  Widget build(BuildContext context) {
    final hasWork = totalOpen > 0;
    final statusText = hasWork
        ? '$totalOpen ${totalOpen == 1 ? 'item needs' : 'items need'} your attention'
        : 'You are all caught up today.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.maroon, AppTheme.maroonDark],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.maroon.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const Positioned(
                top: -20,
                right: -12,
                child: _HeroOrb(size: 100, opacity: 0.1),
              ),
              const Positioned(
                bottom: 16,
                left: -16,
                child: _HeroOrb(size: 72, opacity: 0.07),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (syncing) ...[
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Refreshing dashboard…',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (offlineLabel != null) ...[
                      FieldOfflineBanner(label: offlineLabel!, hint: offlineHint),
                      const SizedBox(height: 12),
                    ],
                    if (error != null) ...[
                      FieldErrorBanner(message: error!, onRetry: onRetry ?? () {}),
                      if (onOpenServer != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: onOpenServer,
                            icon: const Icon(Icons.dns_outlined, size: 18, color: Colors.white),
                            label: const Text(
                              'Check API server',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Hello,',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      firstName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: hasWork ? 0.16 : 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              hasWork ? Icons.pending_actions_rounded : Icons.check_circle_outline_rounded,
                              color: hasWork ? AppTheme.brandOrange : Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 13,
                                fontWeight: hasWork ? FontWeight.w600 : FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (hasWork)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.brandOrange,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$totalOpen',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroOrb extends StatelessWidget {
  const _HeroOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: AppTheme.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ModuleIconTile extends StatelessWidget {
  const _ModuleIconTile({
    required this.module,
    required this.count,
    required this.onTap,
  });

  final MobileModuleInfo module;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.maroonLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(module.icon, color: AppTheme.maroon, size: 26),
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: const BoxDecoration(
                      color: AppTheme.maroon,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            module.gridLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({
    required this.module,
    required this.count,
    required this.onTap,
  });

  final MobileModuleInfo module;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      height: 108,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: AppTheme.maroon.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.maroon,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
                child: SizedBox(width: 4),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.maroonLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(module.icon, color: AppTheme.maroon, size: 20),
                      ),
                      const Spacer(),
                      Text(
                        module.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count open',
                        style: const TextStyle(
                          color: AppTheme.maroon,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
