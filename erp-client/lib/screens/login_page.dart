import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/api_settings.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/server_connection_sheet.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _serverLoaded = false;
  String _serverLabel = ApiSettings.displayHostPort(ApiSettings.builtinDefault);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serverLoaded) return;
    _serverLoaded = true;
    _loadServerLabel();
  }

  Future<void> _loadServerLabel() async {
    await context.read<ApiClient>().ensureConfigured();
    if (!mounted) return;
    setState(() => _serverLabel = ApiSettings.displayHostPort(ApiSettings.current));
  }

  Future<void> _openServerSheet() async {
    await showServerConnectionSheet(context);
    await _loadServerLabel();
  }

  bool get _usesEmulatorLoopback =>
      ApiSettings.current.contains('10.0.2.2');

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthState>();
    final ok = await auth.login(_loginController.text, _passwordController.text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Login failed'),
          backgroundColor: AppTheme.errorText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return Scaffold(
      backgroundColor: AppTheme.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: BrandLogo(
                        size: 72,
                        showLabel: true,
                        centeredLabel: true,
                        labelColor: AppTheme.maroon,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.maroon,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (_usesEmulatorLoopback) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: AppTheme.errorBg,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Still on 10.0.2.2 (emulator-only). The app can search your Wi‑Fi '
                                'for the PC automatically — tap below, or enter your PC IP.',
                                style: TextStyle(color: AppTheme.errorText, fontSize: 13, height: 1.35),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: auth.busy ? null : _openServerSheet,
                                child: const Text('Set PC server address'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (auth.error != null && !_usesEmulatorLoopback) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: AppTheme.errorBg,
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.lock_clock_outlined, color: AppTheme.errorText),
                          title: Text(
                            auth.error!,
                            style: const TextStyle(color: AppTheme.errorText, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _loginController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        floatingLabelStyle: TextStyle(color: AppTheme.maroon),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? 'Enter username' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        floatingLabelStyle: const TextStyle(color: AppTheme.maroon),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      autofillHints: const [AutofillHints.password],
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Enter password' : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(auth.busy ? 'Signing in…' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: auth.busy ? null : _openServerSheet,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: Text(
                        'Server: $_serverLabel',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
