import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_page.dart';
import 'screens/shell_page.dart';
import 'services/api_client.dart';
import 'state/auth_state.dart';
import 'theme/app_theme.dart';
import 'widgets/brand_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RtsErpMobileApp());
}

class RtsErpMobileApp extends StatefulWidget {
  const RtsErpMobileApp({super.key});

  @override
  State<RtsErpMobileApp> createState() => _RtsErpMobileAppState();
}

class _RtsErpMobileAppState extends State<RtsErpMobileApp> {
  late final ApiClient _api;
  late final AuthState _auth;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _auth = AuthState(_api);
    _api.onSessionExpired = _auth.handleSessionExpired;
    _auth.bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        ChangeNotifierProvider<AuthState>.value(value: _auth),
      ],
      child: MaterialApp(
        title: 'ResponsivCode Field',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Consumer<AuthState>(
          builder: (context, auth, _) {
            if (auth.bootstrapping) {
              return const _BootSplash();
            }
            if (!auth.isAuthenticated) {
              return const LoginPage();
            }
            return const ShellPage();
          },
        ),
      ),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.page,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(
              size: 72,
              showLabel: true,
              centeredLabel: true,
              labelColor: AppTheme.maroon,
            ),
            SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.maroon,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
