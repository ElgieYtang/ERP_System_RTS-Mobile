import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/mobile_modules.dart';
import '../services/api_client.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';
import '../navigation/module_shell.dart';
import '../widgets/brand_logo.dart';
import '../widgets/server_connection_sheet.dart';
import 'home_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  ApiClient? _api;
  final _homeKey = GlobalKey<HomePageState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = context.read<ApiClient>();
  }

  Future<void> _openModule(BuildContext context, MobileModule module) async {
    final api = _api;
    if (api == null) return;

    final onModuleShell = ModalRoute.of(context)?.settings.name == 'module';

    if (onModuleShell) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'module'),
          builder: (routeContext) => ModuleShell(
            module: module,
            api: api,
            onOpenModule: _openModule,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'module'),
        builder: (routeContext) => ModuleShell(
          module: module,
          api: api,
          onOpenModule: _openModule,
        ),
      ),
    );

    if (!mounted) return;
    await _homeKey.currentState?.refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      backgroundColor: AppTheme.page,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const BrandLogo(size: 28),
        bottom: PreferredSize(
          preferredSize: Size.zero,
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              child: Text(
                _initials(auth.user?['name']?.toString()),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            onSelected: (value) async {
              if (value == 'server') {
                await showServerConnectionSheet(context);
                await _homeKey.currentState?.refreshCounts();
              } else if (value == 'logout') {
                await auth.logout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?['name']?.toString() ?? 'User',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      auth.user?['login']?.toString() ?? '',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'server', child: Text('API server')),
              const PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: HomePage(
        key: _homeKey,
        onOpenModule: (module) => _openModule(context, module),
      ),
    );
  }

  String _initials(String? name) {
    final parts = (name ?? 'U').trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return (parts.first.isNotEmpty ? parts.first[0] : 'U').toUpperCase();
  }
}
